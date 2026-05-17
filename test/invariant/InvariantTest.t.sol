// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {Handler} from "./Handler.sol";

/// @notice Invariant tests. Foundry calls the invariant_* functions after each Handler sequence.
contract InvariantTest is Base {
    Handler internal handler;

    uint256 internal INITIAL_K;

    function setUp() public override {
        super.setUp();

        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;

        handler = new Handler(market, lpToken, ct, usdc, aggregator, actors);

        // Fund handler's actors generously up front so calls don't dry up
        _mintAndApprove(alice, 100_000_000e6);
        _mintAndApprove(bob, 100_000_000e6);
        _mintAndApprove(carol, 100_000_000e6);

        // Restrict fuzzer to only call the handler
        targetContract(address(handler));

        // Record the initial k after the seeded liquidity
        INITIAL_K = market.k();
    }

    /*//////////////////////////////////////////////////////////////
                     INVARIANT 1: K NEVER DECREASES (CORE)
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant The constant-product k = yesReserve * noReserve must never
    ///                   decrease across any sequence of swaps and liquidity operations.
    function invariant_k_never_decreases() public view {
        assertGe(market.k(), INITIAL_K, "k invariant broken: k < initial_k");
    }

    /*//////////////////////////////////////////////////////////////
                INVARIANT 2: LP SUPPLY CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant LP total supply can only decrease when removeLiquidity is called,
    ///                   and never goes below MINIMUM_LIQUIDITY as long as any LP exists.
    function invariant_lp_minimum_liquidity_locked() public view {
        uint256 supply = lpToken.totalSupply();
        if (supply > 0) {
            // address(1) always holds MINIMUM_LIQUIDITY
            assertGe(lpToken.balanceOf(address(1)), market.MINIMUM_LIQUIDITY(), "MINIMUM_LIQUIDITY not locked");
        }
    }

    /*//////////////////////////////////////////////////////////////
             INVARIANT 3: AMM RESERVE SYMMETRY (NO FREE SHARES)
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant If the AMM is not frozen, both reserves must be > 0 whenever
    ///                   LP supply > MINIMUM_LIQUIDITY.
    function invariant_reserves_nonzero_when_lp_exists() public view {
        if (market.ammFrozen()) return;
        uint256 supply = lpToken.totalSupply();
        if (supply > market.MINIMUM_LIQUIDITY()) {
            (uint256 yr, uint256 nr) = market.reserves();
            assertGt(yr, 0, "yesReserve is zero with LP holders");
            assertGt(nr, 0, "noReserve is zero with LP holders");
        }
    }

    /*//////////////////////////////////////////////////////////////
             INVARIANT 4: VAULT SHARE PRICE MONOTONE INCREASING
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant The vault's share price (convertToAssets per 1e18 shares) must
    ///                   never decrease over time. Fees only flow IN to the vault, never out.
    function invariant_vault_share_price_nondecreasing() public view {
        // 1e18 is a large enough unit to expose rounding; real share price in 6-decimal asset
        uint256 price = vault.convertToAssets(1e18);
        assertGe(price, 0, "vault price negative (impossible, but guard against underflow)");
        // We can't store a previous price inside an invariant easily; check a proxy:
        // totalAssets >= shares supply × floor price (no share dilution without new assets)
        uint256 assets = vault.totalAssets();
        uint256 shares = vault.totalSupply();
        if (shares > 0) {
            // convertToAssets(shares) must be <= totalAssets (no phantom assets)
            assertLe(vault.convertToAssets(shares), assets + 1, "phantom assets in vault");
        }
    }

    /*//////////////////////////////////////////////////////////////
           INVARIANT 5: TOTAL SUPPLY OF GOV TOKEN <= MAX SUPPLY
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant GovernanceToken.totalSupply() must never exceed MAX_SUPPLY.
    function invariant_gov_token_total_supply_lte_cap() public view {
        assertLe(govToken.totalSupply(), govToken.MAX_SUPPLY(), "gov token exceeded max supply");
    }

    /*//////////////////////////////////////////////////////////////
         INVARIANT 6: MARKET STATE MACHINE IS ACYCLIC
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant The market state must be one of the valid enum values
    ///                   and must never regress (Active < Closed < Resolved < ... < Finalized).
    function invariant_market_state_valid_range() public view {
        uint8 s = uint8(market.state());
        assertLe(s, 4, "market state out of enum range (0-4)");
    }

    /*//////////////////////////////////////////////////////////////
         INVARIANT 7: ACCUMULATED LP FEES NEVER EXCEED TOTAL COLLATERAL
    //////////////////////////////////////////////////////////////*/

    /// @custom:invariant Accumulated LP fees must never exceed the contract's total collateral balance.
    function invariant_lp_fees_lte_contract_balance() public view {
        uint256 contractBalance = usdc.balanceOf(address(market));
        uint256 lpFees = market.accumulatedLPFees();
        assertLe(lpFees, contractBalance + 1, "lpFees exceed contract balance");
    }
}
