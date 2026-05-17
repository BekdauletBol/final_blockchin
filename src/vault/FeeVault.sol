// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IFeeVault} from "../interfaces/IFeeVault.sol";

/// @title FeeVault
/// @notice ERC-4626 vault that accumulates protocol-fee revenue denominated in the collateral token.
/// @dev    The vault honours ERC-4626 rounding invariants (convertTo/preview rounding via OZ).
///         Inflation attack defence: OZ v5 ERC4626 uses _decimalsOffset() = 6 — donating
///         dust cannot meaningfully inflate the price-per-share against the first depositor.
///         Sources (the markets / factory) are whitelisted via SOURCE_ROLE; only they can call
///         notifyFee(). The Timelock holds DEFAULT_ADMIN_ROLE and may sweep accumulated assets
///         to the treasury — exposed via sweepTo().
contract FeeVault is ERC4626, AccessControl, IFeeVault {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant SOURCE_ROLE = keccak256("SOURCE_ROLE");

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param asset_  Collateral token (e.g. USDC).
    /// @param admin   Timelock — receives DEFAULT_ADMIN_ROLE.
    /// @param factory Initial source — authorised to call notifyFee on behalf of all markets.
    constructor(IERC20 asset_, address admin, address factory)
        ERC20(
            string(abi.encodePacked("Prediction Fee Vault ", IERC20Metadata(address(asset_)).symbol())),
            string(abi.encodePacked("pfv", IERC20Metadata(address(asset_)).symbol()))
        )
        ERC4626(asset_)
    {
        require(admin != address(0) && factory != address(0), "Zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SOURCE_ROLE, factory);
    }

    /*//////////////////////////////////////////////////////////////
                  INFLATION-ATTACK DEFENCE (OZ virtual offset)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC4626
    function _decimalsOffset() internal pure override returns (uint8) {
        // 6 virtual decimals of dilution => attacker would need to donate 10^6 × the first
        // depositor's stake to inflate the price per share by 1. Effectively unprofitable.
        return 6;
    }

    /*//////////////////////////////////////////////////////////////
                              FEE INTAKE
    //////////////////////////////////////////////////////////////*/

    /// @notice Markets call this after approving `amount` of asset to the vault.
    /// @dev Pulls the approved assets, increasing totalAssets() and lifting share price.
    function notifyFee(uint256 amount) external override onlyRole(SOURCE_ROLE) {
        if (amount == 0) return;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit FeeForwarded(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              SWEEP TO TREASURY
    //////////////////////////////////////////////////////////////*/

    /// @notice Timelock sweeps `shares` worth of assets to the treasury.
    /// @dev Burns vault shares from the vault's own balance — only meaningful once the
    ///      Timelock has earned/holds shares (e.g., via initial seed deposit at bootstrap).
    function sweepTo(address treasury, uint256 shares)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 assetsSent)
    {
        require(treasury != address(0), "Zero treasury");
        // redeem will burn shares from `msg.sender` (the Timelock) and send assets to `treasury`.
        assetsSent = redeem(shares, treasury, msg.sender);
        emit FeesSweptToTreasury(treasury, assetsSent, shares);
    }

    /// @notice Add a new authorised source (e.g., a future product, or an upgraded factory).
    function authorizeSource(address source) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SOURCE_ROLE, source);
    }
}
