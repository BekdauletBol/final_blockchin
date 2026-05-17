// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IFeeVault
/// @notice Tokenised ERC-4626 vault holding protocol-fee revenue.
/// @dev Wraps the collateral token; share price grows as AMMs forward fees.
interface IFeeVault is IERC4626 {
    event FeeForwarded(address indexed source, uint256 amount);
    event FeesSweptToTreasury(address indexed treasury, uint256 assets, uint256 shares);

    error NotAuthorizedSource();

    function notifyFee(uint256 amount) external;
    function sweepTo(address treasury, uint256 shares) external returns (uint256 assetsSent);
    function authorizeSource(address source) external;
}
