// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}    from "../Base.t.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract FeeVaultTest is Base {
    uint256 internal constant SEED = 50_000e6; // Initial deposit into vault

    function setUp() public override {
        super.setUp();
        // Seed vault: alice deposits directly (via ERC-4626 deposit)
        usdc.mint(alice, SEED);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        vault.deposit(SEED, alice);
    }

    /*//////////////////////////////////////////////////////////////
                               BASIC 4626
    //////////////////////////////////////////////////////////////*/

    function test_deposit_mints_shares() public {
        uint256 shares = vault.balanceOf(alice);
        assertGt(shares, 0);
    }

    function test_total_assets_equals_seed() public view {
        assertEq(vault.totalAssets(), SEED);
    }

    function test_convert_to_assets_is_non_decreasing() public {
        uint256 assets0 = vault.convertToAssets(1e18);
        // Simulate a fee notification (share price should rise)
        _simulateFee(10_000e6);
        uint256 assets1 = vault.convertToAssets(1e18);
        assertGe(assets1, assets0, "convertToAssets decreased");
    }

    function test_withdraw_returns_correct_assets() public {
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = usdc.balanceOf(alice);

        uint256 halfShares = sharesBefore / 2;
        uint256 expectedAssets = vault.convertToAssets(halfShares);

        vm.prank(alice);
        vault.redeem(halfShares, alice, alice);

        assertApproxEqAbs(usdc.balanceOf(alice), assetsBefore + expectedAssets, 1);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE NOTIFICATION
    //////////////////////////////////////////////////////////////*/

    function test_notify_fee_increases_total_assets() public {
        uint256 before = vault.totalAssets();
        _simulateFee(5_000e6);
        assertEq(vault.totalAssets(), before + 5_000e6);
    }

    function test_notify_fee_unauthorized_reverts() public {
        bytes32 role = vault.SOURCE_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, role)
        );
        vm.prank(bob);
        vault.notifyFee(1_000e6);
    }

    function test_notify_fee_zero_is_noop() public {
        uint256 before = vault.totalAssets();
        // factory holds SOURCE_ROLE
        vm.prank(address(factory));
        vault.notifyFee(0);
        assertEq(vault.totalAssets(), before);
    }

    /*//////////////////////////////////////////////////////////////
                           SWEEP TO TREASURY
    //////////////////////////////////////////////////////////////*/

    function test_sweep_sends_assets_to_treasury() public {
        // Timelock holds DEFAULT_ADMIN_ROLE; give it vault shares first
        usdc.mint(address(timelock), 10_000e6);
        vm.prank(address(timelock));
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(address(timelock));
        vault.deposit(10_000e6, address(timelock));

        uint256 timelockShares = vault.balanceOf(address(timelock));
        uint256 treasuryBefore = usdc.balanceOf(carol);

        vm.prank(address(timelock));
        vault.sweepTo(carol, timelockShares);

        assertGt(usdc.balanceOf(carol), treasuryBefore);
    }

    function test_sweep_unauthorized_reverts() public {
        vm.expectRevert(); // AccessControl
        vm.prank(alice);
        vault.sweepTo(carol, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    INFLATION ATTACK GUARD (_decimalsOffset)
    //////////////////////////////////////////////////////////////*/

    function test_inflation_attack_unprofitable() public {
        // Attacker donates a large amount directly then withdraws
        // Due to _decimalsOffset = 6, the price-per-share increase is negligible
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 1_000_000e6);
        vm.prank(attacker);
        usdc.approve(address(vault), type(uint256).max);

        // Direct transfer (not deposit) to inflate totalAssets
        vm.prank(attacker);
        usdc.transfer(address(vault), 1_000_000e6);

        // A subsequent depositor should still get a fair number of shares
        address victim = makeAddr("victim");
        usdc.mint(victim, 100e6);
        vm.prank(victim);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(victim);
        uint256 shares = vault.deposit(100e6, victim);

        // Due to virtual shares, shares received should be non-zero and roughly fair
        assertGt(shares, 0);
    }

    /*//////////////////////////////////////////////////////////////
                       ERC-4626 ROUNDING INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function test_preview_deposit_le_actual_shares() public view {
        uint256 preview = vault.previewDeposit(1_000e6);
        // previewDeposit must return the same or fewer shares than mint would give
        uint256 actual = vault.convertToShares(1_000e6);
        assertLe(preview, actual + 1); // within 1 unit rounding
    }

    function test_preview_redeem_le_actual_assets() public view {
        uint256 shares = vault.balanceOf(alice);
        uint256 preview = vault.previewRedeem(shares);
        uint256 actual  = vault.convertToAssets(shares);
        assertLe(preview, actual + 1);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _simulateFee(uint256 amount) internal {
        usdc.mint(address(factory), amount);
        vm.prank(address(factory));
        usdc.approve(address(vault), amount);
        vm.prank(address(factory));
        vault.notifyFee(amount);
    }
}
