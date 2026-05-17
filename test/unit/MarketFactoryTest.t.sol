// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base}           from "../Base.t.sol";
import {MarketFactory}  from "src/market/MarketFactory.sol";
import {PredictionMarket} from "src/market/PredictionMarket.sol";
import {IPredictionMarket} from "src/interfaces/IPredictionMarket.sol";
import {IAccessControl}  from "@openzeppelin/contracts/access/IAccessControl.sol";

contract MarketFactoryTest is Base {

    /*//////////////////////////////////////////////////////////////
                             DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_factory_registers_market_in_allMarkets() public view {
        assertEq(factory.allMarketsLength(), 1);
        assertEq(factory.allMarkets(0), address(market));
    }

    function test_factory_stores_market_by_salt() public view {
        bytes32 salt = keccak256("market-1");
        assertEq(factory.marketBySalt(salt), address(market));
    }

    function test_implementation_pinned() public view {
        assertEq(factory.implementation(), address(impl));
    }

    /*//////////////////////////////////////////////////////////////
                          PREDICT ADDRESS
    //////////////////////////////////////////////////////////////*/

    function test_predict_market_address_matches_deployed() public view {
        bytes32 salt = keccak256("market-1");
        address predicted = factory.predictMarketAddress(salt);
        assertEq(predicted, address(market));
    }

    function test_predict_different_salts_differ() public view {
        address a = factory.predictMarketAddress(keccak256("salt-a"));
        address b = factory.predictMarketAddress(keccak256("salt-b"));
        assertNotEq(a, b);
    }

    /*//////////////////////////////////////////////////////////////
                          DUPLICATE SALT
    //////////////////////////////////////////////////////////////*/

    function test_duplicate_salt_reverts() public {
        bytes32 salt = keccak256("market-1");
        vm.expectRevert(MarketFactory.SaltAlreadyUsed.selector);
        factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       address(usdc),
                oracle:                address(resolver),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "Dupe",
                lpName:                "LP DUPE",
                lpSymbol:              "LP-D",
                salt:                  salt
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                           ROLE GATING
    //////////////////////////////////////////////////////////////*/

    function test_unauthorized_creator_reverts() public {
        bytes32 role = factory.CREATOR_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role)
        );
        vm.prank(alice);
        factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       address(usdc),
                oracle:                address(resolver),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "Unauthorised",
                lpName:                "LP UNAUTH",
                lpSymbol:              "LP-U",
                salt:                  keccak256("unauth-salt")
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MARKET INITIALISATION
    //////////////////////////////////////////////////////////////*/

    function test_market_admin_is_timelock() public view {
        assertTrue(market.hasRole(market.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    function test_market_upgrader_is_timelock() public view {
        assertTrue(market.hasRole(market.UPGRADER_ROLE(), address(timelock)));
    }

    function test_market_pauser_is_multisig() public view {
        assertTrue(market.hasRole(market.PAUSER_ROLE(), multisig));
    }

    function test_market_collateral_set_correctly() public view {
        IPredictionMarket.MarketInfo memory i = market.info();
        assertEq(i.collateralToken, address(usdc));
    }

    function test_market_conditional_tokens_set() public view {
        assertEq(address(market.conditionalTokens()), address(ct));
    }

    function test_lp_token_bound_to_market() public view {
        assertEq(lpToken.market(), address(market));
    }

    function test_market_is_authorized_in_conditional_tokens() public view {
        assertTrue(ct.isAuthorizedMarket(address(market)));
    }

    /*//////////////////////////////////////////////////////////////
                          SECOND MARKET DEPLOY
    //////////////////////////////////////////////////////////////*/

    function test_second_market_gets_unique_address() public {
        (address market2,) = factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       address(usdc),
                oracle:                address(resolver),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "Second market",
                lpName:                "LP #2",
                lpSymbol:              "PRED-LP-2",
                salt:                  keccak256("market-2")
            })
        );
        assertNotEq(market2, address(market));
        assertEq(factory.allMarketsLength(), 2);
    }
}
