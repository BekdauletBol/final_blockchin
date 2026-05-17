// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PredictionTimelock
/// @notice 2-day timelock controller that owns protocol treasury and admin keys.
/// @dev    Spec requires minDelay = 172_800 seconds. We enforce that at deployment to prevent misconfig.
///         Proposers MUST be the Governor; executors should be address(0) (anyone can execute once queued).
contract PredictionTimelock is TimelockController {
    /// @dev Constant matched to spec — Governor mid-project review can verify on-chain.
    uint256 public constant REQUIRED_MIN_DELAY = 2 days;

    error WrongMinDelay(uint256 supplied, uint256 required);

    /// @param minDelay  Must equal REQUIRED_MIN_DELAY.
    /// @param proposers Should contain the Governor only.
    /// @param executors Should contain address(0) only (open execution after delay).
    /// @param admin    The temporary admin during bootstrap; renounce after wiring is done.
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {
        if (minDelay != REQUIRED_MIN_DELAY) {
            revert WrongMinDelay(minDelay, REQUIRED_MIN_DELAY);
        }
    }
}
