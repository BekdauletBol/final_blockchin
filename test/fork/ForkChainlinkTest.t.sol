// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ChainlinkResolver} from "src/oracle/ChainlinkResolver.sol";

/// @notice Fork test — reads from live Chainlink ETH/USD on Arbitrum mainnet.
///         Run with: forge test --match-contract ForkChainlinkTest --fork-url $ARBITRUM_RPC_URL -vvv
contract ForkChainlinkTest is Test {
    // Chainlink ETH/USD on Arbitrum One
    address internal constant ETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    AggregatorV3Interface internal feed;
    ChainlinkResolver internal resolver;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        feed = AggregatorV3Interface(ETH_USD_FEED);
        resolver = new ChainlinkResolver(feed, 1 hours, "ETH/USD Arb mainnet");
    }

    function test_fork_chainlink_decimals_is_8() public view {
        assertEq(feed.decimals(), 8);
    }

    function test_fork_chainlink_price_is_positive() public view {
        (int256 price,,) = resolver.latestPrice();
        console2.log("ETH/USD price:", price);
        assertGt(price, 0, "price is not positive");
    }

    function test_fork_chainlink_price_plausible() public view {
        (int256 price,,) = resolver.latestPrice();
        // ETH price should be between $100 and $100 000 (8 decimals)
        assertGt(price, 100e8, unicode"price < $100 — implausible");
        assertLt(price, 100_000e8, unicode"price > $100 000 — implausible");
    }

    function test_fork_chainlink_updated_recently() public view {
        (, uint256 updatedAt,) = resolver.latestPrice();
        console2.log("Last updated:", updatedAt, "now:", block.timestamp);
        // Feed should not be stale by more than the resolver's staleAfter (1 hour)
        assertLe(block.timestamp - updatedAt, 1 hours, "feed is stale on mainnet fork");
    }

    function test_fork_chainlink_resolve_above_zero_threshold() public view {
        // Any positive ETH price is above $0
        (bool above,,) = resolver.resolveAgainstThreshold(0);
        assertTrue(above, "ETH price is not above $0");
    }

    function test_fork_chainlink_resolve_below_million_threshold() public view {
        // ETH is definitely < $1 000 000
        (bool above,,) = resolver.resolveAgainstThreshold(1_000_000e8);
        assertFalse(above, unicode"ETH price is above $1 000 000 — very unexpected");
    }

    function test_fork_chainlink_round_data_consistent() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        console2.log("roundId:", roundId, "answeredInRound:", answeredInRound);
        assertGe(answeredInRound, roundId - 10, "round sequence drift too large");
        assertGt(answer, 0, "answer is non-positive");
        assertGt(updatedAt, 0, "updatedAt is zero");
    }
}
