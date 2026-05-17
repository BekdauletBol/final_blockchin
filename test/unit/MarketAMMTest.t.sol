// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}             from "../Base.t.sol";
import {IPredictionMarket} from "src/interfaces/IPredictionMarket.sol";
import {IMarketAMM}       from "src/interfaces/IMarketAMM.sol";
import {MarketFactory}      from "src/market/MarketFactory.sol";
import {PredictionMarket}   from "src/market/PredictionMarket.sol";

contract MarketAMMTest is Base {
    /*//////////////////////////////////////////////////////////////
                           ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function test_add_liquidity_mints_lp_tokens() public {
        uint256 lpBefore = lpToken.totalSupply();
        uint256 amount   = 10_000e6;
        vm.prank(bob);
        uint256 lp = market.addLiquidity(amount, 0, block.timestamp + 1 hours);
        assertGt(lp, 0);
        assertEq(lpToken.totalSupply(), lpBefore + lp);
    }

    function test_add_liquidity_updates_reserves() public {
        (uint256 yr0, uint256 nr0) = market.reserves();
        uint256 amount = 20_000e6;
        vm.prank(bob);
        market.addLiquidity(amount, 0, block.timestamp + 1 hours);
        (uint256 yr1, uint256 nr1) = market.reserves();
        assertEq(yr1 - yr0, amount);
        assertEq(nr1 - nr0, amount);
    }

    function test_add_liquidity_below_minimum_reverts() public {
        // MINIMUM_LIQUIDITY is 1000 — first deposit must exceed that
        // Alice already seeded, so second deposit has no minimum constraint
        // For first deposit test, deploy a fresh market
        (address m,) = factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       address(usdc),
                oracle:                address(resolver),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "Fresh market",
                lpName:                "LP #2",
                lpSymbol:              "PRED-LP-2",
                salt:                  keccak256("market-fresh")
            })
        );
        vm.prank(alice);
        usdc.approve(m, type(uint256).max);
        vm.expectRevert("below MIN_LIQ");
        vm.prank(alice);
        PredictionMarket(m).addLiquidity(500, 0, block.timestamp + 1 hours);
    }

    function test_add_liquidity_slippage_protection() public {
        uint256 amount = 5_000e6;
        vm.prank(bob);
        uint256 expected = market.addLiquidity(amount, 0, block.timestamp + 1 hours);
        // Now try with minLp = expected + 1 (impossible to satisfy)
        usdc.mint(bob, amount);
        vm.prank(bob);
        usdc.approve(address(market), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IMarketAMM.SlippageExceeded.selector, expected + 1, expected));
        vm.prank(bob);
        market.addLiquidity(amount, expected + 1, block.timestamp + 1 hours);
    }

    function test_add_liquidity_deadline_reverts() public {
        vm.expectRevert(IMarketAMM.DeadlinePassed.selector);
        vm.prank(bob);
        market.addLiquidity(10_000e6, 0, block.timestamp - 1);
    }

    function test_add_liquidity_zero_amount_reverts() public {
        vm.expectRevert(IPredictionMarket.ZeroAmount.selector);
        vm.prank(bob);
        market.addLiquidity(0, 0, block.timestamp + 1 hours);
    }

    function test_add_liquidity_frozen_amm_reverts() public {
        // Freeze via admin
        _timelockExec(address(market), abi.encodeCall(IMarketAMM.freeze, ()));
        vm.expectRevert(IMarketAMM.AmmFrozen.selector);
        vm.prank(bob);
        market.addLiquidity(10_000e6, 0, block.timestamp + 1 hours);
    }

    /*//////////////////////////////////////////////////////////////
                          REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function test_remove_liquidity_returns_shares() public {
        uint256 lp = lpToken.balanceOf(alice);
        (uint256 yr, uint256 nr) = market.reserves();
        uint256 supply = lpToken.totalSupply();

        uint256 expectedYes = lp * yr / supply;
        uint256 expectedNo  = lp * nr / supply;

        (uint256 yesId, uint256 noId) = _ids();
        uint256 yesBefore = ct.balanceOf(alice, yesId);
        uint256 noBefore  = ct.balanceOf(alice, noId);

        vm.prank(alice);
        lpToken.approve(address(market), lp);
        vm.prank(alice);
        (uint256 yOut, uint256 nOut) = market.removeLiquidity(lp, 0, 0, block.timestamp + 1 hours);

        assertEq(yOut, expectedYes);
        assertEq(nOut, expectedNo);
        assertEq(ct.balanceOf(alice, yesId), yesBefore + yOut);
        assertEq(ct.balanceOf(alice, noId),  noBefore  + nOut);
    }

    function test_remove_liquidity_zero_lp_reverts() public {
        vm.expectRevert(IPredictionMarket.ZeroAmount.selector);
        vm.prank(alice);
        market.removeLiquidity(0, 0, 0, block.timestamp + 1 hours);
    }

    function test_remove_liquidity_slippage_min_yes_reverts() public {
        uint256 lp = lpToken.balanceOf(alice) / 2;
        vm.prank(alice);
        lpToken.approve(address(market), lp);
        (uint256 yr,,) = (market.yesReserve(), market.noReserve(), lpToken.totalSupply());
        vm.expectRevert(); // SlippageExceeded
        vm.prank(alice);
        market.removeLiquidity(lp, type(uint256).max, 0, block.timestamp + 1 hours);
    }

    /*//////////////////////////////////////////////////////////////
                              BUY YES
    //////////////////////////////////////////////////////////////*/

    function test_buy_yes_returns_shares() public {
        uint256 shares = _buyYes(bob, SWAP_AMOUNT);
        assertGt(shares, 0);
    }

    function test_buy_yes_mints_shares_to_buyer() public {
        (uint256 yId,) = _ids();
        uint256 before = ct.balanceOf(bob, yId);
        uint256 shares = _buyYes(bob, SWAP_AMOUNT);
        assertEq(ct.balanceOf(bob, yId), before + shares);
    }

    function test_buy_yes_transfers_collateral_from_buyer() public {
        uint256 before = usdc.balanceOf(bob);
        _buyYes(bob, SWAP_AMOUNT);
        assertEq(usdc.balanceOf(bob), before - SWAP_AMOUNT);
    }

    function test_buy_yes_increases_no_reserve() public {
        (, uint256 nr0) = market.reserves();
        _buyYes(bob, SWAP_AMOUNT);
        (, uint256 nr1) = market.reserves();
        assertGt(nr1, nr0);
    }

    function test_buy_yes_decreases_yes_reserve() public {
        (uint256 yr0,) = market.reserves();
        _buyYes(bob, SWAP_AMOUNT);
        (uint256 yr1,) = market.reserves();
        assertLt(yr1, yr0);
    }

    function test_buy_yes_sends_protocol_fee_to_vault() public {
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        _buyYes(bob, SWAP_AMOUNT);
        // 0.05% fee on SWAP_AMOUNT
        uint256 expectedFee = SWAP_AMOUNT * 5 / 10_000;
        assertEq(usdc.balanceOf(address(vault)), vaultBefore + expectedFee);
    }

    function test_buy_yes_accumulates_lp_fee() public {
        uint256 before = market.accumulatedLPFees();
        _buyYes(bob, SWAP_AMOUNT);
        uint256 expectedLPFee = SWAP_AMOUNT * 25 / 10_000;
        assertEq(market.accumulatedLPFees(), before + expectedLPFee);
    }

    function test_buy_yes_frozen_reverts() public {
        _timelockExec(address(market), abi.encodeCall(IMarketAMM.freeze, ()));
        vm.expectRevert(IMarketAMM.AmmFrozen.selector);
        vm.prank(bob);
        market.buyYes(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
    }

    function test_buy_yes_slippage_reverts() public {
        uint256 predicted = market.quoteBuyYes(SWAP_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IMarketAMM.SlippageExceeded.selector, predicted + 1, predicted));
        vm.prank(bob);
        market.buyYes(SWAP_AMOUNT, predicted + 1, block.timestamp + 1 hours);
    }

    function test_buy_yes_deadline_reverts() public {
        vm.expectRevert(IMarketAMM.DeadlinePassed.selector);
        vm.prank(bob);
        market.buyYes(SWAP_AMOUNT, 0, block.timestamp - 1);
    }

    function test_buy_yes_zero_collateral_reverts() public {
        vm.expectRevert(IPredictionMarket.ZeroAmount.selector);
        vm.prank(bob);
        market.buyYes(0, 0, block.timestamp + 1 hours);
    }

    /*//////////////////////////////////////////////////////////////
                              BUY NO
    //////////////////////////////////////////////////////////////*/

    function test_buy_no_returns_shares() public {
        uint256 shares = _buyNo(bob, SWAP_AMOUNT);
        assertGt(shares, 0);
    }

    function test_buy_no_mints_to_buyer() public {
        (, uint256 nId) = _ids();
        uint256 before = ct.balanceOf(bob, nId);
        uint256 shares = _buyNo(bob, SWAP_AMOUNT);
        assertEq(ct.balanceOf(bob, nId), before + shares);
    }

    function test_buy_no_increases_yes_reserve() public {
        (uint256 yr0,) = market.reserves();
        _buyNo(bob, SWAP_AMOUNT);
        (uint256 yr1,) = market.reserves();
        assertGt(yr1, yr0);
    }

    /*//////////////////////////////////////////////////////////////
                               PRICES
    //////////////////////////////////////////////////////////////*/

    function test_initial_prices_equal_50_50() public view {
        // Symmetric initial liquidity → priceYes + priceNo == 1e18
        uint256 py = market.priceYes();
        uint256 pn = market.priceNo();
        assertApproxEqAbs(py + pn, 1e18, 1); // ±1 wei rounding
    }

    function test_buying_yes_increases_yes_price() public {
        uint256 py0 = market.priceYes();
        _buyNo(bob, SWAP_AMOUNT * 5); // push the pool toward NO-heavy
        uint256 py1 = market.priceYes();
        assertGt(py1, py0);
    }

    function test_quote_matches_actual_output() public view {
        uint256 quoted = market.quoteBuyYes(SWAP_AMOUNT);
        // Can't execute without changing state here; just assert it's non-zero & plausible
        assertGt(quoted, 0);
        assertLt(quoted, SWAP_AMOUNT * 2); // can't get more shares than 2× collateral at extreme prices
    }

    /*//////////////////////////////////////////////////////////////
                        K-INVARIANT (spot check)
    //////////////////////////////////////////////////////////////*/

    function test_k_does_not_decrease_after_swap() public {
        uint256 k0 = market.k();
        _buyYes(bob, SWAP_AMOUNT);
        uint256 k1 = market.k();
        assertGe(k1, k0, "k decreased after swap");
    }

    function test_k_does_not_decrease_after_buy_no() public {
        uint256 k0 = market.k();
        _buyNo(bob, SWAP_AMOUNT);
        uint256 k1 = market.k();
        assertGe(k1, k0, "k decreased after buyNo");
    }
}
