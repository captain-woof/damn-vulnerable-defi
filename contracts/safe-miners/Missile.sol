// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Missile {
    function transferTokens(IERC20 _token) external {
        _token.transfer(tx.origin, _token.balanceOf(address(this)));
    }
}
