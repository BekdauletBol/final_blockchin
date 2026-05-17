// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";

import {PredictionMarket} from "src/market/PredictionMarket.sol";
import {LPToken} from "src/tokens/LPToken.sol";
import {ConditionalTokens} from "src/tokens/ConditionalTokens.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockAggregator} from "src/mocks/MockAggregator.sol";

/// @notice Stateful handler called by the invariant fuzzer.
contract Handler is CommonBase, StdCheats, StdUtils {
    PredictionMarket internal market;
    LPToken internal lpToken;
    ConditionalTokens internal ct;
    MockERC20 internal usdc;
    MockAggregator internal agg;

    address[] internal actors;
    uint256 internal constant MAX_COLLATERAL = 500_000e6;

    // Ghost variables — tracked state that invariants reference.
    uint256 public ghost_totalCollateralIn;
    uint256 public ghost_totalProtocolFees;
    uint256 public ghost_totalLPFees;

    constructor(
        PredictionMarket market_,
        LPToken lpToken_,
        ConditionalTokens ct_,
        MockERC20 usdc_,
        MockAggregator agg_,
        address[] memory actors_
    ) {
        market = market_;
        lpToken = lpToken_;
        ct = ct_;
        usdc = usdc_;
        agg = agg_;
        actors = actors_;
    }

    /*//////////////////////////////////////////////////////////////
                              ACTIONS
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 1000e6, MAX_COLLATERAL);
        if (market.ammFrozen()) return;
        usdc.mint(actor, amount);
        vm.prank(actor);
        usdc.approve(address(market), amount);
        vm.prank(actor);
        try market.addLiquidity(amount, 0, block.timestamp + 1 hours) {
            ghost_totalCollateralIn += amount;
        } catch {}
    }

    function buyYes(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 1e6, 50_000e6);
        if (market.ammFrozen() || market.paused()) return;
        usdc.mint(actor, amount);
        vm.prank(actor);
        usdc.approve(address(market), amount);
        vm.prank(actor);
        try market.buyYes(amount, 0, block.timestamp + 1 hours) {
            uint256 fee = amount * 5 / 10_000;
            ghost_totalProtocolFees += fee;
            ghost_totalLPFees += amount * 25 / 10_000;
            ghost_totalCollateralIn += amount;
        } catch {}
    }

    function buyNo(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 1e6, 50_000e6);
        if (market.ammFrozen() || market.paused()) return;
        usdc.mint(actor, amount);
        vm.prank(actor);
        usdc.approve(address(market), amount);
        vm.prank(actor);
        try market.buyNo(amount, 0, block.timestamp + 1 hours) {
            ghost_totalProtocolFees += amount * 5 / 10_000;
            ghost_totalLPFees += amount * 25 / 10_000;
            ghost_totalCollateralIn += amount;
        } catch {}
    }

    function removeLiquidity(uint256 actorSeed, uint256 lpPct) external {
        address actor = _actor(actorSeed);
        uint256 lp = lpToken.balanceOf(actor);
        if (lp == 0) return;
        lpPct = bound(lpPct, 1, 100);
        uint256 toRemove = lp * lpPct / 100;
        if (toRemove == 0) return;
        vm.prank(actor);
        lpToken.approve(address(market), toRemove);
        vm.prank(actor);
        try market.removeLiquidity(toRemove, 0, 0, block.timestamp + 1 hours) {} catch {}
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 0, 14 days);
        vm.warp(block.timestamp + seconds_);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
}
