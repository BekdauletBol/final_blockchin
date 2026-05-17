// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}             from "../Base.t.sol";
import {ChainlinkResolver} from "src/oracle/ChainlinkResolver.sol";
import {MockAggregator}   from "src/mocks/MockAggregator.sol";

contract ChainlinkResolverTest is Base {
    ChainlinkResolver internal localResolver;
    MockAggregator    internal localAgg;

    function setUp() public override {
        super.setUp();
        localAgg      = new MockAggregator(THRESHOLD + 1, 8, "Test/USD");
        localResolver = new ChainlinkResolver(localAgg, 2 hours, "Test feed");
    }

    /*//////////////////////////////////////////////////////////////
                               DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_description() public view {
        assertEq(localResolver.description(), "Test feed");
    }

    function test_decimals() public view {
        assertEq(localResolver.decimals(), 8);
    }

    function test_zero_feed_reverts() public {
        vm.expectRevert(ChainlinkResolver.InvalidFeed.selector);
        new ChainlinkResolver(MockAggregator(address(0)), 1 hours, "");
    }

    function test_stale_after_zero_reverts() public {
        vm.expectRevert("staleAfter out of range");
        new ChainlinkResolver(localAgg, 0, "");
    }

    function test_stale_after_too_large_reverts() public {
        vm.expectRevert("staleAfter out of range");
        new ChainlinkResolver(localAgg, 8 days, "");
    }

    /*//////////////////////////////////////////////////////////////
                              LATEST PRICE
    //////////////////////////////////////////////////////////////*/

    function test_latest_price_returns_current() public view {
        (int256 price, uint256 updatedAt, uint256 stale) = localResolver.latestPrice();
        assertEq(price, THRESHOLD + 1);
        assertEq(stale, 2 hours);
        assertEq(updatedAt, block.timestamp);
    }

    function test_latest_price_reverts_on_stale() public {
        // Advance time past staleAfter
        localAgg.setAnswerStale(THRESHOLD + 1, 2 hours + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkResolver.StalePrice.selector,
                block.timestamp - (2 hours + 1),
                2 hours
            )
        );
        localResolver.latestPrice();
    }

    function test_latest_price_reverts_on_negative() public {
        localAgg.setAnswer(-1);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkResolver.NegativeOrZeroPrice.selector, -1));
        localResolver.latestPrice();
    }

    function test_latest_price_reverts_on_zero_price() public {
        localAgg.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkResolver.NegativeOrZeroPrice.selector, 0));
        localResolver.latestPrice();
    }

    function test_latest_price_reverts_on_round_mismatch() public {
        localAgg.setRoundMismatch(THRESHOLD + 1);
        vm.expectRevert(); // InvalidRound
        localResolver.latestPrice();
    }

    /*//////////////////////////////////////////////////////////////
                         RESOLVE AGAINST THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function test_resolve_above_threshold_is_yes() public view {
        localAgg; // price set to THRESHOLD + 1 in setUp
        (bool above,,) = localResolver.resolveAgainstThreshold(THRESHOLD);
        assertTrue(above);
    }

    function test_resolve_at_threshold_is_no() public {
        // strictly above ⟹ not equal
        localAgg.setAnswer(THRESHOLD);
        (bool above,,) = localResolver.resolveAgainstThreshold(THRESHOLD);
        assertFalse(above);
    }

    function test_resolve_below_threshold_is_no() public {
        localAgg.setAnswer(THRESHOLD - 1);
        (bool above,,) = localResolver.resolveAgainstThreshold(THRESHOLD);
        assertFalse(above);
    }

    function test_resolve_returns_price_used() public view {
        (, int256 price,) = localResolver.resolveAgainstThreshold(THRESHOLD);
        assertEq(price, THRESHOLD + 1);
    }

    function test_resolve_returns_timestamp() public view {
        (,, uint256 t) = localResolver.resolveAgainstThreshold(THRESHOLD);
        assertEq(t, block.timestamp);
    }
}
