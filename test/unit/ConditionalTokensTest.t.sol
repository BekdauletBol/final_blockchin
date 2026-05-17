// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {ConditionalTokens} from "src/tokens/ConditionalTokens.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ConditionalTokensTest is Base {
    /*//////////////////////////////////////////////////////////////
                         CONDITION PREPARATION
    //////////////////////////////////////////////////////////////*/

    function test_market_has_unique_yes_no_ids() public view {
        (uint256 yId, uint256 nId) = ct.getIds(address(market));
        assertNotEq(yId, nId);
        assertNotEq(yId, 0);
        assertNotEq(nId, 0);
    }

    function test_id_derivation_is_deterministic() public view {
        (uint256 yId,) = ct.getIds(address(market));
        uint256 expected = uint256(keccak256(abi.encode(address(market), uint8(1))));
        assertEq(yId, expected);
    }

    function test_prepare_condition_unauthorized_reverts() public {
        bytes32 role = ct.FACTORY_ROLE();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        vm.prank(alice);
        ct.prepareCondition(makeAddr("newMarket"));
    }

    function test_prepare_condition_twice_reverts() public {
        // Factory tries to re-register the same market
        vm.expectRevert(IConditionalTokens.ConditionAlreadyPrepared.selector);
        vm.prank(address(factory));
        ct.prepareCondition(address(market));
    }

    function test_market_is_authorized_after_creation() public view {
        assertTrue(ct.isAuthorizedMarket(address(market)));
    }

    function test_arbitrary_address_is_not_authorized() public view {
        assertFalse(ct.isAuthorizedMarket(alice));
    }

    /*//////////////////////////////////////////////////////////////
                            MINT / BURN
    //////////////////////////////////////////////////////////////*/

    function test_mint_complete_creates_both_shares() public {
        uint256 amount = 1000e6;
        (uint256 yId, uint256 nId) = _ids();

        uint256 yesBefore = ct.balanceOf(bob, yId);
        uint256 noBefore = ct.balanceOf(bob, nId);

        // Market mints on behalf of bob (market is the msg.sender)
        vm.prank(address(market));
        ct.mintComplete(bob, amount);

        assertEq(ct.balanceOf(bob, yId), yesBefore + amount);
        assertEq(ct.balanceOf(bob, nId), noBefore + amount);
    }

    function test_mint_unauthorized_reverts() public {
        vm.expectRevert(IConditionalTokens.NotAuthorizedMarket.selector);
        vm.prank(alice);
        ct.mintComplete(alice, 1000e6);
    }

    function test_burn_single_yes_decreases_balance() public {
        uint256 amount = 500e6;
        vm.prank(address(market));
        ct.mintComplete(bob, amount);

        (uint256 yId,) = _ids();
        uint256 yesBefore = ct.balanceOf(bob, yId);

        vm.prank(address(market));
        ct.burnSingle(
            bob,
            1,
            /* YES */
            amount
        );
        assertEq(ct.balanceOf(bob, yId), yesBefore - amount);
    }

    function test_burn_single_invalid_outcome_index_reverts() public {
        vm.prank(address(market));
        ct.mintComplete(bob, 1000e6);
        vm.expectRevert(abi.encodeWithSelector(IConditionalTokens.InvalidOutcomeIndex.selector, 3));
        vm.prank(address(market));
        ct.burnSingle(bob, 3, 1000e6);
    }

    function test_burn_complete_removes_both() public {
        uint256 amount = 300e6;
        vm.prank(address(market));
        ct.mintComplete(bob, amount);

        (uint256 yId, uint256 nId) = _ids();
        vm.prank(address(market));
        ct.burnComplete(bob, amount);

        assertEq(ct.balanceOf(bob, yId), 0);
        assertEq(ct.balanceOf(bob, nId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC165 SUPPORT
    //////////////////////////////////////////////////////////////*/

    function test_supports_erc1155_interface() public view {
        assertTrue(ct.supportsInterface(type(IERC1155).interfaceId));
    }

    function test_supports_access_control_interface() public view {
        assertTrue(ct.supportsInterface(type(IAccessControl).interfaceId));
    }
}

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
