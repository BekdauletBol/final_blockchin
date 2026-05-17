// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOracleResolver
/// @notice Generic outcome-resolution oracle. Implemented by ChainlinkResolver and MockResolver.
/// @dev Adapter pattern — the market only sees this interface, not the underlying source.
interface IOracleResolver {
    /// @notice Pull the latest price answer and metadata.
    /// @return price            The oracle price (signed).
    /// @return updatedAt        The unix timestamp of last update.
    /// @return staleAfterSeconds Maximum acceptable staleness; revert if older.
    function latestPrice() external view returns (int256 price, uint256 updatedAt, uint256 staleAfterSeconds);

    /// @notice Resolve the market outcome based on the threshold supplied at market creation.
    /// @param threshold The threshold price the market is compared against.
    /// @return resolvedAbove True if oracle price strictly above threshold (YES wins).
    function resolveAgainstThreshold(int256 threshold)
        external
        view
        returns (bool resolvedAbove, int256 priceUsed, uint256 priceTime);

    function description() external view returns (string memory);
    function decimals() external view returns (uint8);
}
