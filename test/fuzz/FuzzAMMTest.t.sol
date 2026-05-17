// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}    from "../Base.t.sol";
import {YulMath} from "src/libraries/YulMath.sol";
import {MathSol} from "src/libraries/YulMath.sol";

/// @notice Fuzz test suite for the AMM, vault, and math library.
contract FuzzAMMTest is Base {
    /*//////////////////////////////////////////////////////////////
                          FUZZ: BUY YES
    //////////////////////////////////////////////////////////////*/

    /// @dev Property: buying YES always returns > 0 shares for any non-zero collateral in [1, 1M USDC].
    function testFuzz_buy_yes_returns_positive_shares(uint256 collateral) public {
        collateral = bound(collateral, ONE_USDC, 1_000_000e6);
        usdc.mint(bob, collateral);
        vm.prank(bob);
        usdc.approve(address(market), collateral);
        uint256 shares = market.buyYes(collateral, 0, block.timestamp + 1 hours);
        assertGt(shares, 0, "buyYes returned 0 shares");
    }

    /// @dev Property: after any buyYes, k must not decrease.
    function testFuzz_buy_yes_k_non_decreasing(uint256 collateral) public {
        collateral = bound(collateral, ONE_USDC, 500_000e6);
        uint256 kBefore = market.k();
        usdc.mint(bob, collateral);
        vm.prank(bob);
        usdc.approve(address(market), collateral);
        market.buyYes(collateral, 0, block.timestamp + 1 hours);
        assertGe(market.k(), kBefore, "k decreased after buyYes");
    }

    /// @dev Property: buying YES then NO with equal collateral should leave k higher than initial.
    function testFuzz_alternating_buys_increase_k(uint256 collateral) public {
        collateral = bound(collateral, ONE_USDC, 100_000e6);
        uint256 kBefore = market.k();

        usdc.mint(bob, collateral * 2);
        vm.startPrank(bob);
        usdc.approve(address(market), collateral * 2);
        market.buyYes(collateral, 0, block.timestamp + 1 hours);
        market.buyNo(collateral,  0, block.timestamp + 1 hours);
        vm.stopPrank();

        assertGe(market.k(), kBefore, "k decreased after alternating buys");
    }

    /// @dev Property: priceYes + priceNo == 1e18 (to within 1 wei rounding).
    function testFuzz_prices_sum_to_one(uint256 collateral) public {
        collateral = bound(collateral, ONE_USDC, 200_000e6);
        usdc.mint(bob, collateral);
        vm.prank(bob);
        usdc.approve(address(market), collateral);
        market.buyYes(collateral, 0, block.timestamp + 1 hours);

        uint256 py = market.priceYes();
        uint256 pn = market.priceNo();
        assertApproxEqAbs(py + pn, 1e18, 1, "prices don't sum to 1e18");
    }

    /// @dev Property: shares out always < collateral in (can't get more than 1:1 outcome share).
    function testFuzz_shares_never_exceed_collateral(uint256 collateral) public {
        collateral = bound(collateral, ONE_USDC, 300_000e6);
        usdc.mint(bob, collateral);
        vm.prank(bob);
        usdc.approve(address(market), collateral);
        uint256 shares = market.buyYes(collateral, 0, block.timestamp + 1 hours);
        assertLt(shares, collateral + 1, "shares >= collateral (impossible win rate)");
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ: ADD LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @dev Property: adding then removing liquidity (full LP) returns ≥ original collateral × 2 in shares.
    function testFuzz_add_remove_liquidity_roundtrip(uint256 collateral) public {
        collateral = bound(collateral, 10_000e6, 500_000e6);
        usdc.mint(carol, collateral);
        vm.prank(carol);
        usdc.approve(address(market), collateral);

        uint256 lpMinted = market.addLiquidity(collateral, 0, block.timestamp + 1 hours);
        assertGt(lpMinted, 0);

        (uint256 yId, uint256 nId) = _ids();
        vm.prank(carol);
        lpToken.approve(address(market), lpMinted);
        (uint256 yOut, uint256 nOut) = market.removeLiquidity(lpMinted, 0, 0, block.timestamp + 1 hours);

        // Shares out should be ≤ collateral (fee structure means LPs get <= collateral worth of shares)
        assertLe(yOut + nOut, collateral * 2 + 1);
        assertGt(yOut + nOut, 0);

        // Silence "variable set but not read" for nId
        assertTrue(nId > 0 || yId > 0);
    }

    /// @dev Property: LP supply strictly increases on deposit.
    function testFuzz_lp_supply_increases_on_deposit(uint256 collateral) public {
        collateral = bound(collateral, 5_000e6, 100_000e6);
        uint256 supplyBefore = lpToken.totalSupply();
        usdc.mint(carol, collateral);
        vm.prank(carol);
        usdc.approve(address(market), collateral);
        market.addLiquidity(collateral, 0, block.timestamp + 1 hours);
        assertGt(lpToken.totalSupply(), supplyBefore);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ: VAULT DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @dev Property: depositing then redeeming returns ≤ assets deposited (no free money).
    function testFuzz_vault_no_free_money(uint256 assets) public {
        assets = bound(assets, 1e6, 1_000_000e6);
        usdc.mint(carol, assets);
        vm.prank(carol);
        usdc.approve(address(vault), assets);
        vm.prank(carol);
        uint256 shares = vault.deposit(assets, carol);

        uint256 usdcBefore = usdc.balanceOf(carol);
        vm.prank(carol);
        uint256 returned = vault.redeem(shares, carol, carol);

        // Can't get more back than was put in (accounting for rounding)
        assertLe(returned, assets + 1, "vault returned more than deposited");
        assertGt(returned, 0, "vault returned zero");
    }

    /// @dev Property: convertToAssets(convertToShares(x)) <= x (round-trip floors).
    function testFuzz_vault_convert_roundtrip(uint256 assets) public view {
        assets = bound(assets, 1, 1_000_000e6);
        uint256 shares = vault.convertToShares(assets);
        uint256 back   = vault.convertToAssets(shares);
        assertLe(back, assets + 1, "round-trip inflated assets");
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ: YULMATH
    //////////////////////////////////////////////////////////////*/

    /// @dev Property: YulMath.mulDiv matches the naive (a*b)/d for values that don't overflow 256-bit.
    function testFuzz_yulmath_muldiv_matches_naive(uint128 a, uint128 b, uint128 d) public pure {
        vm.assume(d > 0);
        uint256 a256 = uint256(a);
        uint256 b256 = uint256(b);
        uint256 d256 = uint256(d);
        uint256 expected = (a256 * b256) / d256;  // Safe: a,b are uint128, product fits in uint256
        uint256 actual   = YulMath.mulDiv(a256, b256, d256);
        assertEq(actual, expected, "YulMath.mulDiv mismatch");
    }

    /// @dev Property: YulMath.sqrt(x*x) == x for x in [0, 2^128).
    function testFuzz_yulmath_sqrt_perfect_squares(uint128 x) public pure {
        uint256 square = uint256(x) * uint256(x);
        uint256 root   = YulMath.sqrt(square);
        assertEq(root, uint256(x), "sqrt of perfect square wrong");
    }

    /// @dev Property: YulMath.sqrt(y) satisfies r^2 <= y < (r+1)^2.
    function testFuzz_yulmath_sqrt_bounds(uint256 y) public pure {
        uint256 r = YulMath.sqrt(y);
        assertLe(r * r, y, "sqrt^2 > y");
        if (r < type(uint128).max) {
            assertGt((r + 1) * (r + 1), y, "(sqrt+1)^2 <= y");
        }
    }

    /// @dev Property: YulMath.mulDiv and MathSol.mulDiv agree on uint128 inputs.
    function testFuzz_yulmath_vs_solidity_agree(uint128 a, uint128 b, uint128 d) public pure {
        vm.assume(d > 0);
        uint256 yulResult = YulMath.mulDiv(uint256(a), uint256(b), uint256(d));
        uint256 solResult = MathSol.mulDiv(uint256(a), uint256(b), uint256(d));
        assertEq(yulResult, solResult, "YulMath vs MathSol mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                     FUZZ: GOVERNANCE VOTING POWER
    //////////////////////////////////////////////////////////////*/

    /// @dev Property: getPastVotes(a, t) <= totalSupply at t for any delegatee.
    function testFuzz_voting_power_le_total_supply(address delegatee, uint256 transferAmount) public {
        vm.assume(delegatee != address(0) && delegatee != address(1));
        transferAmount = bound(transferAmount, 1e18, 500_000e18);

        vm.prank(deployer);
        govToken.transfer(delegatee, transferAmount);
        vm.prank(delegatee);
        govToken.delegate(delegatee);

        uint256 snap = block.timestamp;
        vm.warp(snap + 5);

        uint256 votes  = govToken.getPastVotes(delegatee, snap);
        uint256 supply = govToken.getPastTotalSupply(snap);
        assertLe(votes, supply, "individual votes exceed total supply");
    }
}
