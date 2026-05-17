// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {GovernanceToken} from "src/governance/GovernanceToken.sol";
import {IAccessControl}  from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GovernanceTokenTest is Base {
    /*//////////////////////////////////////////////////////////////
                              DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_name_and_symbol() public view {
        assertEq(govToken.name(),   "Prediction DAO Token");
        assertEq(govToken.symbol(), "PRED");
    }

    function test_initial_supply_minted_to_deployer() public view {
        // deployer received 10 M; then transferred 1.5 M to alice+bob in setUp
        assertEq(govToken.balanceOf(deployer), 10_000_000e18 - 1_500_000e18);
    }

    function test_max_supply_constant() public view {
        assertEq(govToken.MAX_SUPPLY(), 100_000_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING
    //////////////////////////////////////////////////////////////*/

    function test_mint_requires_minter_role() public {
        bytes32 role = govToken.MINTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role)
        );
        vm.prank(alice);
        govToken.mint(alice, 1e18);
    }

    function test_mint_respects_max_supply() public {
        // Timelock holds MINTER_ROLE; simulate via prank
        uint256 remaining = govToken.MAX_SUPPLY() - govToken.totalSupply();
        vm.prank(address(timelock));
        govToken.mint(alice, remaining); // fills up to cap — OK

        // One more token must revert
        vm.expectRevert(
            abi.encodeWithSelector(GovernanceToken.MaxSupplyExceeded.selector, govToken.MAX_SUPPLY() + 1, govToken.MAX_SUPPLY())
        );
        vm.prank(address(timelock));
        govToken.mint(alice, 1);
    }

    function test_mint_increases_balance() public {
        uint256 before = govToken.balanceOf(carol);
        uint256 amount = 100e18;
        vm.prank(address(timelock));
        govToken.mint(carol, amount);
        assertEq(govToken.balanceOf(carol), before + amount);
    }

    /*//////////////////////////////////////////////////////////////
                          DELEGATION & VOTES
    //////////////////////////////////////////////////////////////*/

    function test_voting_power_zero_before_delegation() public view {
        // carol never delegated
        assertEq(govToken.getVotes(carol), 0);
    }

    function test_voting_power_after_self_delegation() public {
        // deployer already delegated in setUp — transfer some to carol then delegate
        vm.prank(deployer);
        govToken.transfer(carol, 200e18);
        vm.prank(carol);
        govToken.delegate(carol);
        assertEq(govToken.getVotes(carol), 200e18);
    }

    function test_delegation_transfers_voting_power() public {
        vm.prank(deployer);
        govToken.transfer(carol, 1_000e18);
        vm.prank(carol);
        govToken.delegate(alice);

        // alice's power should increase by carol's balance
        assertGe(govToken.getVotes(alice), govToken.balanceOf(carol));
    }

    function test_past_votes_recorded_at_snapshot() public {
        uint256 snapshot = block.timestamp;
        vm.warp(block.timestamp + 10);
        // alice's votes at snapshot == her balance at that point
        uint256 pastVotes = govToken.getPastVotes(alice, snapshot);
        assertEq(pastVotes, govToken.balanceOf(alice));
    }

    /*//////////////////////////////////////////////////////////////
                               CLOCK
    //////////////////////////////////////////////////////////////*/

    function test_clock_returns_timestamp() public view {
        assertEq(govToken.clock(), uint48(block.timestamp));
    }

    function test_clock_mode_is_timestamp() public view {
        assertEq(govToken.CLOCK_MODE(), "mode=timestamp");
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT (EIP-2612)
    //////////////////////////////////////////////////////////////*/

    function test_permit_allows_gasless_approval() public {
        // Build & sign EIP-2612 permit from alice
        uint256 value   = 500e18;
        uint256 nonce   = govToken.nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice, address(market), value, nonce, deadline
        );

        govToken.permit(alice, address(market), value, deadline, v, r, s);
        assertEq(govToken.allowance(alice, address(market)), value);
    }

    function test_permit_reverts_on_wrong_signer() public {
        uint256 nonce    = govToken.nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;
        // Sign with bob's key but supply alice's permit
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(bob, address(market), 100e18, nonce, deadline);

        vm.expectRevert();
        govToken.permit(alice, address(market), 100e18, deadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _signPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = govToken.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner, spender, value, nonce, deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        uint256 privKey = uint256(keccak256(abi.encodePacked(owner))); // deterministic test key
        (v, r, s) = vm.sign(privKey, digest);
    }
}
