// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}               from "../Base.t.sol";
import {PredictionMarket}   from "src/market/PredictionMarket.sol";
import {PredictionMarketV2} from "src/market/PredictionMarketV2.sol";
import {IPredictionMarket}  from "src/interfaces/IPredictionMarket.sol";
import {IAccessControl}     from "@openzeppelin/contracts/access/IAccessControl.sol";

contract UUPSUpgradeTest is Base {

    PredictionMarketV2 internal v2Impl;
    PredictionMarketV2 internal marketV2; // same proxy, new type

    function setUp() public override {
        super.setUp();
        // Deploy V2 implementation
        v2Impl = new PredictionMarketV2();
        // Perform upgrade as Timelock
        _timelockExec(
            address(market),
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(v2Impl), "")
        );
        marketV2 = PredictionMarketV2(address(market));
    }

    /*//////////////////////////////////////////////////////////////
                         V1 STATE PRESERVED
    //////////////////////////////////////////////////////////////*/

    function test_upgrade_preserves_question() public view {
        assertEq(marketV2.question(), "Will ETH be above $3000 by next week?");
    }

    function test_upgrade_preserves_threshold() public view {
        assertEq(marketV2.thresholdPrice(), THRESHOLD);
    }

    function test_upgrade_preserves_collateral_token() public view {
        assertEq(address(marketV2.collateralToken()), address(usdc));
    }

    function test_upgrade_preserves_reserves() public view {
        (uint256 yr, uint256 nr) = marketV2.reserves();
        assertEq(yr, INITIAL_LIQ);
        assertEq(nr, INITIAL_LIQ);
    }

    function test_upgrade_preserves_state_active() public view {
        assertEq(uint8(marketV2.state()), uint8(IPredictionMarket.MarketState.Active));
    }

    function test_upgrade_preserves_lp_token() public view {
        assertEq(address(marketV2.lpToken()), address(lpToken));
    }

    function test_upgrade_preserves_roles() public view {
        assertTrue(marketV2.hasRole(marketV2.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    /*//////////////////////////////////////////////////////////////
                           V2 NEW STATE
    //////////////////////////////////////////////////////////////*/

    function test_v2_cumulative_volume_starts_zero() public view {
        assertEq(marketV2.cumulativeVolume(), 0);
    }

    function test_v2_unique_traders_starts_zero() public view {
        assertEq(marketV2.uniqueTraders(), 0);
    }

    function test_v2_records_volume_on_buy_yes() public {
        vm.prank(bob);
        marketV2.buyYes(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
        assertEq(marketV2.cumulativeVolume(), SWAP_AMOUNT);
    }

    function test_v2_counts_unique_traders() public {
        vm.prank(bob);
        marketV2.buyYes(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
        vm.prank(carol);
        marketV2.buyNo(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
        assertEq(marketV2.uniqueTraders(), 2);
    }

    function test_v2_does_not_double_count_trader() public {
        vm.prank(bob);
        marketV2.buyYes(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
        vm.prank(bob);
        marketV2.buyNo(SWAP_AMOUNT, 0, block.timestamp + 1 hours);
        assertEq(marketV2.uniqueTraders(), 1);
    }

    function test_v2_version_string() public view {
        assertEq(marketV2.version(), "2.0.0");
    }

    /*//////////////////////////////////////////////////////////////
                       REINITIALIZER
    //////////////////////////////////////////////////////////////*/

    function test_reinitializer_v2_callable_by_anyone() public {
        // reinitializer(2) is a one-shot; calling again should revert
        marketV2.initializeV2(); // first call (may revert if already called in upgrade)
    }

    function test_reinitializer_v2_second_call_reverts() public {
        try marketV2.initializeV2() {} catch {}
        vm.expectRevert(); // InvalidInitialization
        marketV2.initializeV2();
    }

    /*//////////////////////////////////////////////////////////////
                         UNAUTHORIZED UPGRADE
    //////////////////////////////////////////////////////////////*/

    function test_unauthorized_upgrade_reverts() public {
        PredictionMarketV2 newImpl = new PredictionMarketV2();
        bytes32 role = market.UPGRADER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role)
        );
        vm.prank(alice);
        market.upgradeToAndCall(address(newImpl), "");
    }

    /*//////////////////////////////////////////////////////////////
                       IMPLEMENTATION CANNOT BE INITIALIZED
    //////////////////////////////////////////////////////////////*/

    function test_implementation_initializer_disabled() public {
        PredictionMarket freshImpl = new PredictionMarket();
        vm.expectRevert(); // InvalidInitialization (disableInitializers in constructor)
        freshImpl.initialize(
            IPredictionMarket.InitParams({
                admin:                 deployer,
                pauser:                deployer,
                upgrader:              deployer,
                collateralToken:       address(usdc),
                conditionalTokens:     address(ct),
                oracle:                address(resolver),
                feeVault:              address(vault),
                lpToken:               address(lpToken),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "should fail"
            })
        );
    }
}
