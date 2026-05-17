// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IMarketAMM
/// @notice Constant-product AMM specialised for binary outcome shares (YES / NO).
/// @dev Reserves are denominated in outcome shares minted 1:1 against collateral.
///      Invariant: yesReserve * noReserve == k (mod fees).
interface IMarketAMM {
    event LiquidityAdded(address indexed provider, uint256 collateralIn, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 lpBurned, uint256 yesOut, uint256 noOut);
    event Swap(
        address indexed trader,
        bool buyYes,
        uint256 collateralIn,
        uint256 sharesOut,
        uint256 feeToVault,
        uint256 feeToLPs
    );

    error InsufficientLiquidity();
    error SlippageExceeded(uint256 expected, uint256 received);
    error KInvariantViolated(uint256 kBefore, uint256 kAfter);
    error AmmFrozen();
    error DeadlinePassed();

    function addLiquidity(uint256 collateralAmount, uint256 minLp, uint256 deadline)
        external
        returns (uint256 lpMinted);

    function removeLiquidity(uint256 lpAmount, uint256 minYes, uint256 minNo, uint256 deadline)
        external
        returns (uint256 yesOut, uint256 noOut);

    function buyYes(uint256 collateralIn, uint256 minSharesOut, uint256 deadline)
        external
        returns (uint256 yesOut);

    function buyNo(uint256 collateralIn, uint256 minSharesOut, uint256 deadline)
        external
        returns (uint256 noOut);

    function reserves() external view returns (uint256 yesReserve, uint256 noReserve);
    function k() external view returns (uint256);
    function priceYes() external view returns (uint256);
    function priceNo() external view returns (uint256);
    function quoteBuyYes(uint256 collateralIn) external view returns (uint256 yesOut);
    function quoteBuyNo(uint256 collateralIn) external view returns (uint256 noOut);

    function freeze() external;
}
