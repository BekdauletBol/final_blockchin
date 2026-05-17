// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {IPredictionMarket} from "src/interfaces/IPredictionMarket.sol";

contract ClaimTest is Base {
    function setUp() public override {
        super.setUp();
        // Bob buys YES; Carol buys NO
        _buyYes(bob, SWAP_AMOUNT);
        _buyNo(carol, SWAP_AMOUNT);
        // Approve ConditionalTokens for burning
        _approveCT(bob);
        _approveCT(carol);
    }

    /*//////////////////////////////////////////////////////////////
                              YES WINS
    //////////////////////////////////////////////////////////////*/

    function test_claim_yes_outcome_returns_collateral() public {
        _finalizeYes();
        (uint256 yId,) = _ids();
        uint256 yesBal = ct.balanceOf(bob, yId);
        uint256 before = usdc.balanceOf(bob);

        vm.prank(bob);
        uint256 returned = market.claim();

        assertEq(returned, yesBal);
        assertEq(usdc.balanceOf(bob), before + returned);
    }

    function test_claim_yes_burns_yes_shares() public {
        _finalizeYes();
        (uint256 yId,) = _ids();
        uint256 yesBal = ct.balanceOf(bob, yId);
        assertGt(yesBal, 0);

        vm.prank(bob);
        market.claim();

        assertEq(ct.balanceOf(bob, yId), 0);
    }

    function test_claim_yes_loser_gets_nothing() public {
        _finalizeYes();
        vm.expectRevert(IPredictionMarket.NothingToClaim.selector);
        vm.prank(carol);
        market.claim();
    }

    function test_winnings_for_returns_yes_balance() public {
        _finalizeYes();
        (uint256 yId,) = _ids();
        uint256 yesBal = ct.balanceOf(bob, yId);
        assertEq(market.winningsFor(bob), yesBal);
    }

    /*//////////////////////////////////////////////////////////////
                              NO WINS
    //////////////////////////////////////////////////////////////*/

    function test_claim_no_outcome_returns_collateral() public {
        _finalizeNo();
        (, uint256 nId) = _ids();
        uint256 noBal = ct.balanceOf(carol, nId);
        uint256 before = usdc.balanceOf(carol);

        vm.prank(carol);
        uint256 returned = market.claim();

        assertEq(returned, noBal);
        assertEq(usdc.balanceOf(carol), before + returned);
    }

    function test_claim_no_loser_reverts() public {
        _finalizeNo();
        vm.expectRevert(IPredictionMarket.NothingToClaim.selector);
        vm.prank(bob);
        market.claim();
    }

    function test_winnings_for_returns_no_balance() public {
        _finalizeNo();
        (, uint256 nId) = _ids();
        assertEq(market.winningsFor(carol), ct.balanceOf(carol, nId));
    }

    /*//////////////////////////////////////////////////////////////
                            INVALID OUTCOME
    //////////////////////////////////////////////////////////////*/

    function test_claim_invalid_outcome_50_50() public {
        _resolveYes();
        market.dispute("Manipulated");
        // Governance resolves as Invalid
        _timelockExec(
            address(market), abi.encodeCall(IPredictionMarket.governanceResolve, (IPredictionMarket.Outcome.Invalid))
        );

        (uint256 yId, uint256 nId) = _ids();
        uint256 yesBal = ct.balanceOf(bob, yId);
        uint256 noBal = ct.balanceOf(carol, nId);

        vm.prank(bob);
        uint256 bobReturned = market.claim();
        // 50% of YES balance (rounded down)
        assertEq(bobReturned, yesBal / 2);

        vm.prank(carol);
        uint256 carolReturned = market.claim();
        assertEq(carolReturned, noBal / 2);
    }

    /*//////////////////////////////////////////////////////////////
                         DOUBLE CLAIM PREVENTION
    //////////////////////////////////////////////////////////////*/

    function test_double_claim_reverts() public {
        _finalizeYes();
        vm.prank(bob);
        market.claim();
        // Second claim should revert because shares are burned
        vm.expectRevert(IPredictionMarket.NothingToClaim.selector);
        vm.prank(bob);
        market.claim();
    }

    function test_claim_before_finalized_reverts() public {
        _resolveYes();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPredictionMarket.InvalidState.selector,
                IPredictionMarket.MarketState.Finalized,
                IPredictionMarket.MarketState.Resolved
            )
        );
        vm.prank(bob);
        market.claim();
    }

    function test_winnings_for_returns_zero_before_finalized() public view {
        assertEq(market.winningsFor(bob), 0);
    }
}
