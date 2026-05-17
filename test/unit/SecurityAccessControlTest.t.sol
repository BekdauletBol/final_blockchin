// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IPredictionMarket} from "src/interfaces/IPredictionMarket.sol";

/*//////////////////////////////////////////////////////////////
      VULNERABLE CONTRACT (before-fix version for reproduction)
//////////////////////////////////////////////////////////////*/

/// @notice Unguarded market resolver — any caller can resolve the outcome.
///         Demonstrates why every privileged function MUST use AccessControl.
contract VulnerableMarketResolver {
    bool public resolved;
    bool public outcome;
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    /// @dev VULNERABLE: no access control — any address can call this.
    function resolve(bool _outcome) external {
        resolved = true;
        outcome = _outcome;
    }

    /// @dev ALSO VULNERABLE: uses tx.origin (banned by spec) instead of msg.sender.
    function adminActionViaOrigin() external {
        require(tx.origin == admin, "not admin via origin");
        // Malicious contract can call this and pass because tx.origin == EOA (admin)
        outcome = false;
    }
}

/*//////////////////////////////////////////////////////////////
      FIXED CONTRACT: role-gated resolution in PredictionMarket
//////////////////////////////////////////////////////////////*/

contract SecurityAccessControlTest is Base {
    VulnerableMarketResolver internal vulnResolver;

    function setUp() public override {
        super.setUp();
        vulnResolver = new VulnerableMarketResolver();
    }

    /*---------- Before-fix: attacker resolves vulnerable contract ----------*/

    function test_access_control_vulnerable_anyone_can_resolve() public {
        // Attacker (random address) resolves with a false outcome
        vm.prank(alice);
        vulnResolver.resolve(false); // should succeed — no access control!
        assertTrue(vulnResolver.resolved(), "should have resolved");
        assertFalse(vulnResolver.outcome(), "attacker set wrong outcome");
    }

    function test_access_control_vulnerable_tx_origin_attack() public {
        // Simulate: alice is the admin (deploy from alice)
        vm.prank(alice);
        VulnerableMarketResolver local = new VulnerableMarketResolver();

        // Attacker contract can call adminActionViaOrigin when alice (admin) calls a third-party contract
        // that in turn calls adminActionViaOrigin — tx.origin stays as alice.
        // We demonstrate this is dangerous by calling directly from a prank:
        vm.prank(alice); // tx.origin = alice = admin — any relay would exploit this
        local.adminActionViaOrigin(); // succeeds because tx.origin == admin
        assertFalse(local.outcome());
    }

    /*---------- After-fix: PredictionMarket access control ----------*/

    function test_access_control_governance_resolve_requires_admin() public {
        _resolveYes();
        market.dispute("Dispute!");

        // Random user cannot call governanceResolve
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, market.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        market.governanceResolve(IPredictionMarket.Outcome.No);

        // Only Timelock can — demonstrated in MarketStateMachineTest
        assertEq(uint8(market.state()), uint8(IPredictionMarket.MarketState.Disputed));
    }

    function test_access_control_pause_requires_pauser_role() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, market.PAUSER_ROLE())
        );
        vm.prank(bob);
        market.pause();
        assertFalse(market.paused());
    }

    function test_access_control_upgrade_requires_upgrader_role() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, carol, market.UPGRADER_ROLE()
            )
        );
        vm.prank(carol);
        market.upgradeToAndCall(address(0xBEEF), "");
    }

    function test_access_control_freeze_requires_admin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, market.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        market.freeze();
        assertFalse(market.ammFrozen());
    }

    function test_access_control_timelock_can_freeze() public {
        assertFalse(market.ammFrozen());
        _timelockExec(address(market), abi.encodeCall(market.freeze, ()));
        assertTrue(market.ammFrozen());
    }

    function test_access_control_conditional_tokens_mint_requires_market() public {
        vm.expectRevert(abi.encodeWithSelector(IConditionalTokens.NotAuthorizedMarket.selector));
        vm.prank(alice);
        ct.mintComplete(alice, 1000e6);
    }

    function test_access_control_fee_vault_notify_requires_source_role() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, vault.SOURCE_ROLE())
        );
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(address(vault), 1000e6);
        vm.prank(alice);
        vault.notifyFee(1000e6);
    }

    function test_access_control_no_tx_origin_in_market() public {
        // Verify market admin functions check msg.sender, not tx.origin.
        // Deploy an intermediary contract that calls governanceResolve
        OriginForwarder forwarder = new OriginForwarder(address(market));
        _resolveYes();
        market.dispute("Test tx.origin");

        // Timelock calls forwarder which calls governanceResolve
        // msg.sender in market = forwarder, not timelock → must revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(forwarder),
                market.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(address(timelock)); // tx.origin = timelock (EOA), msg.sender = timelock
        // But if forwarder is called first, msg.sender in market = forwarder, not timelock
        forwarder.relayResolve(IPredictionMarket.Outcome.No);
    }
}

/// @notice Intermediary contract: tests that msg.sender (not tx.origin) is checked.
contract OriginForwarder {
    address internal market;

    constructor(address m) {
        market = m;
    }

    function relayResolve(IPredictionMarket.Outcome o) external {
        IPredictionMarket(market).governanceResolve(o);
    }
}

import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
