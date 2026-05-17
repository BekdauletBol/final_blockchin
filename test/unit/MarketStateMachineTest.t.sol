// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {IPredictionMarket} from "src/interfaces/IPredictionMarket.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MarketStateMachineTest is Base {
    /*//////////////////////////////////////////////////////////////
                            INITIAL STATE
    //////////////////////////////////////////////////////////////*/

    function test_initial_state_is_active() public view {
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Active));
    }

    function test_initial_outcome_is_unresolved() public view {
        assertEq(uint8(market.outcome()), uint8(IPredictionMarket.Outcome.Unresolved));
    }

    function test_market_info_question() public view {
        IPredictionMarket.MarketInfo memory i = market.info();
        assertEq(i.question, "Will ETH be above $3000 by next week?");
    }

    function test_collateral_token_set_correctly() public view {
        IPredictionMarket.MarketInfo memory i = market.info();
        assertEq(i.collateralToken, address(usdc));
    }

    /*//////////////////////////////////////////////////////////////
                          ACTIVE → CLOSED
    //////////////////////////////////////////////////////////////*/

    function test_close_before_time_reverts() public {
        vm.expectRevert(IPredictionMarket.MarketNotClosed.selector);
        market.close();
    }

    function test_close_after_time_succeeds() public {
        vm.warp(block.timestamp + CLOSE_DELAY + 1);
        market.close();
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Closed));
    }

    function test_close_freezes_amm() public {
        vm.warp(block.timestamp + CLOSE_DELAY + 1);
        market.close();
        assertTrue(market.ammFrozen());
    }

    function test_close_twice_reverts() public {
        vm.warp(block.timestamp + CLOSE_DELAY + 1);
        market.close();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPredictionMarket.InvalidState.selector,
                IPredictionMarket.MarketState.Active,
                IPredictionMarket.MarketState.Closed
            )
        );
        market.close();
    }

    /*//////////////////////////////////////////////////////////////
                         CLOSED → RESOLVED
    //////////////////////////////////////////////////////////////*/

    function test_resolve_requires_closed_state() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPredictionMarket.InvalidState.selector,
                IPredictionMarket.MarketState.Closed,
                IPredictionMarket.MarketState.Active
            )
        );
        market.resolve();
    }

    function test_resolve_yes_when_price_above_threshold() public {
        _closeMarket();
        market.resolve();
        assertEq(uint8(market.outcome()), uint8(IPredictionMarket.Outcome.Yes));
    }

    function test_resolve_no_when_price_below_threshold() public {
        aggregator.setAnswer(PRICE_BELOW);
        _closeMarket();
        market.resolve();
        assertEq(uint8(market.outcome()), uint8(IPredictionMarket.Outcome.No));
    }

    function test_resolve_reverts_on_stale_oracle() public {
        aggregator.setAnswerStale(PRICE_ABOVE, 2 hours);
        vm.warp(block.timestamp + CLOSE_DELAY + 1);
        market.close();
        vm.expectRevert(); // ChainlinkResolver.StalePrice
        market.resolve();
    }

    function test_resolve_sets_dispute_window_end() public {
        _closeMarket();
        uint256 t = block.timestamp;
        market.resolve();
        assertEq(market.disputeWindowEnd(), t + DISPUTE_WIN);
    }

    /*//////////////////////////////////////////////////////////////
                         RESOLVED → DISPUTED
    //////////////////////////////////////////////////////////////*/

    function test_dispute_within_window_succeeds() public {
        _resolveYes();
        market.dispute("Price was manipulated");
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Disputed));
    }

    function test_dispute_after_window_reverts() public {
        _resolveYes();
        vm.warp(block.timestamp + DISPUTE_WIN + 1);
        vm.expectRevert(IPredictionMarket.MarketStillInDisputeWindow.selector);
        market.dispute("Too late");
    }

    /*//////////////////////////////////////////////////////////////
                         RESOLVED → FINALIZED
    //////////////////////////////////////////////////////////////*/

    function test_finalize_within_window_reverts() public {
        _resolveYes();
        vm.expectRevert(IPredictionMarket.MarketStillInDisputeWindow.selector);
        market.finalize();
    }

    function test_finalize_after_window_succeeds() public {
        _finalizeYes();
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                       GOVERNANCE RESOLVE (DISPUTED)
    //////////////////////////////////////////////////////////////*/

    function test_governance_resolve_disputed_market() public {
        _resolveYes();
        market.dispute("Dispute!");
        _timelockExec(
            address(market), abi.encodeCall(IPredictionMarket.governanceResolve, (IPredictionMarket.Outcome.No))
        );
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Finalized));
        assertEq(uint8(market.outcome()), uint8(IPredictionMarket.Outcome.No));
    }

    function test_governance_resolve_unresolved_outcome_reverts() public {
        _resolveYes();
        market.dispute("Dispute!");
        vm.expectRevert(IPredictionMarket.InvalidOutcome.selector);
        _timelockExec(
            address(market), abi.encodeCall(IPredictionMarket.governanceResolve, (IPredictionMarket.Outcome.Unresolved))
        );
    }

    function test_governance_resolve_requires_admin_role() public {
        _resolveYes();
        market.dispute("Dispute!");
        bytes32 role = market.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        vm.prank(alice);
        market.governanceResolve(IPredictionMarket.Outcome.No);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE / UNPAUSE
    //////////////////////////////////////////////////////////////*/

    function test_pause_halts_trading() public {
        vm.prank(multisig);
        market.pause();
        assertTrue(market.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(bob);
        market.buyYes(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
    }

    function test_unpause_resumes_trading() public {
        vm.prank(multisig);
        market.pause();
        vm.prank(multisig);
        market.unpause();
        assertFalse(market.paused());
        _buyYes(bob, SWAP_AMOUNT); // should not revert
    }

    function test_pause_requires_pauser_role() public {
        bytes32 role = market.PAUSER_ROLE();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, role));
        vm.prank(bob);
        market.pause();
    }

    function test_remove_liquidity_allowed_while_paused() public {
        vm.prank(multisig);
        market.pause();
        uint256 lp = lpToken.balanceOf(alice);
        vm.prank(alice);
        lpToken.approve(address(market), lp);
        // Should succeed — emergency exit is intentionally not blocked by pause
        vm.prank(alice);
        market.removeLiquidity(lp / 2, 0, 0, block.timestamp + 1 hours);
    }
}
