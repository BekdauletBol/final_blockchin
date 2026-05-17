// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IOracleResolver} from "../interfaces/IOracleResolver.sol";

/// @title ChainlinkResolver
/// @notice Oracle adapter that wraps a Chainlink AggregatorV3 feed and enforces staleness.
/// @dev    Markets call resolveAgainstThreshold to obtain a boolean outcome.
///         The adapter pattern keeps PredictionMarket oracle-agnostic — we can plug in UMA, Pyth, etc.
contract ChainlinkResolver is IOracleResolver {
    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    AggregatorV3Interface public immutable feed;
    uint256 public immutable staleAfter;
    string  private _description;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidFeed();
    error StalePrice(uint256 updatedAt, uint256 maxAge);
    error InvalidRound(uint80 roundId, uint80 answeredInRound);
    error NegativeOrZeroPrice(int256 price);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param feed_       Chainlink aggregator (e.g. ETH/USD on Arbitrum Sepolia).
    /// @param staleAfter_ Maximum acceptable answer age in seconds.
    /// @param description_ Human-readable label for UI/subgraph.
    constructor(AggregatorV3Interface feed_, uint256 staleAfter_, string memory description_) {
        if (address(feed_) == address(0)) revert InvalidFeed();
        require(staleAfter_ > 0 && staleAfter_ <= 7 days, "staleAfter out of range");
        feed = feed_;
        staleAfter = staleAfter_;
        _description = description_;
    }

    /*//////////////////////////////////////////////////////////////
                              READ FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOracleResolver
    function latestPrice()
        external
        view
        override
        returns (int256 price, uint256 updatedAt, uint256 staleAfterSeconds)
    {
        (price, updatedAt) = _safeLatest();
        staleAfterSeconds = staleAfter;
    }

    /// @inheritdoc IOracleResolver
    function resolveAgainstThreshold(int256 threshold)
        external
        view
        override
        returns (bool resolvedAbove, int256 priceUsed, uint256 priceTime)
    {
        (priceUsed, priceTime) = _safeLatest();
        resolvedAbove = priceUsed > threshold;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function decimals() external view override returns (uint8) {
        return feed.decimals();
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reads the latest round, then asserts:
    ///      1. updatedAt is non-zero (round complete)
    ///      2. answeredInRound >= roundId (no out-of-order rounds)
    ///      3. price > 0
    ///      4. now - updatedAt <= staleAfter
    function _safeLatest() internal view returns (int256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        if (_updatedAt == 0) revert InvalidRound(roundId, answeredInRound);
        if (answeredInRound < roundId) revert InvalidRound(roundId, answeredInRound);
        if (answer <= 0) revert NegativeOrZeroPrice(answer);
        if (block.timestamp - _updatedAt > staleAfter) revert StalePrice(_updatedAt, staleAfter);

        return (answer, _updatedAt);
    }
}
