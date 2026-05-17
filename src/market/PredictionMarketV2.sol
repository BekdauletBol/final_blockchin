// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PredictionMarket} from "./PredictionMarket.sol";

/// @title PredictionMarketV2
/// @notice Demonstration V2 implementation showing the UUPS upgrade path.
/// @dev    Adds cumulative volume tracking + unique trader counter via the _afterTrade hook
///         introduced in V1.  No storage variables removed or reordered — see ARCHITECTURE.md
///         §"Storage layout proof" for the exact diff.
///
///         Storage rules followed:
///           1. Existing V1 variables left intact.
///           2. New V2 variables appended AFTER V1's __gap.  This consumes three of the gap's
///              forty empty slots — slots 41, 42, 43 (mapping uses one slot for its base pointer).
///           3. _disableInitializers() in V1's constructor still applies (inherited).
///           4. Re-initialisation goes through reinitializer(2).
contract PredictionMarketV2 is PredictionMarket {
    /*//////////////////////////////////////////////////////////////
                          V2 NEW STATE (APPENDED)
    //////////////////////////////////////////////////////////////*/

    /// @notice Cumulative trading volume in collateral units.
    uint256 public cumulativeVolume;

    /// @notice Number of unique addresses that have ever traded.
    uint256 public uniqueTraders;

    /// @notice Trader → has-traded-before flag (for uniqueTraders accounting).
    mapping(address => bool) public hasTraded;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event V2VolumeRecorded(address indexed trader, uint256 collateralIn, uint256 cumulative);

    /*//////////////////////////////////////////////////////////////
                          V2 RE-INITIALISER
    //////////////////////////////////////////////////////////////*/

    /// @notice Bootstrap V2-only fields. Called once per market after the upgrade by Timelock.
    /// @dev Uses OZ reinitializer(2) — version MUST be strictly greater than V1's (1).
    function initializeV2() external reinitializer(2) {
        // No state needs non-zero defaults — counters start at 0 by definition.
    }

    /*//////////////////////////////////////////////////////////////
                       HOOK OVERRIDE: VOLUME TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc PredictionMarket
    function _afterTrade(
        address trader,
        bool,
        /*isYes*/
        uint256 collateralIn,
        uint256 /*sharesOut*/
    )
        internal
        override
    {
        cumulativeVolume += collateralIn;
        if (!hasTraded[trader]) {
            hasTraded[trader] = true;
            unchecked {
                ++uniqueTraders;
            }
        }
        emit V2VolumeRecorded(trader, collateralIn, cumulativeVolume);
    }

    /*//////////////////////////////////////////////////////////////
                                   VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Version pin for off-chain consumers / Etherscan readability.
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
