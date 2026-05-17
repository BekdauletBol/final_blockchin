// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockAggregator
/// @notice Test-only Chainlink aggregator mock; tests can set any price, age, or round mismatch.
contract MockAggregator is AggregatorV3Interface {
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId = 1;
    uint80 private _answeredInRound = 1;
    uint8 private immutable _decimals;
    string private _desc;

    constructor(int256 initialAnswer, uint8 decimals_, string memory desc) {
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _decimals = decimals_;
        _desc = desc;
    }

    /*------------------- Test-only setters -------------------*/

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
        unchecked {
            _roundId++;
            _answeredInRound = _roundId;
        }
    }

    function setAnswerStale(int256 newAnswer, uint256 ageSeconds) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp - ageSeconds;
        unchecked {
            _roundId++;
            _answeredInRound = _roundId;
        }
    }

    /// @dev Force an inconsistent round so resolver staleness check exercises the bad-round branch.
    function setRoundMismatch(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
        unchecked {
            _roundId++;
        }
        _answeredInRound = _roundId - 1; // older round answered later — bad
    }

    /*--------------------- IAggregatorV3 ---------------------*/

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _desc;
    }

    function version() external pure override returns (uint256) {
        return 4;
    }

    function getRoundData(uint80 _round)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_round, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}
