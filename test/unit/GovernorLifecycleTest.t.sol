// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "../Base.t.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract GovernorLifecycleTest is Base {
    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function test_voting_delay_is_one_day() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_voting_period_is_one_week() public view {
        assertEq(governor.votingPeriod(), 1 weeks);
    }

    function test_quorum_is_4_percent() public {
        // Snapshot taken at block.timestamp - 1
        uint256 ts = block.timestamp;
        vm.warp(ts + 10);
        uint256 q = governor.quorum(ts);
        uint256 expected = govToken.getPastTotalSupply(ts) * 4 / 100;
        assertApproxEqAbs(q, expected, 1e16); // within 0.01 token
    }

    function test_proposal_threshold_is_1_percent() public view {
        uint256 threshold = governor.proposalThreshold();
        uint256 ts = block.timestamp;
        uint256 totalSupply = govToken.getPastTotalSupply(ts > 0 ? ts - 1 : ts);
        assertApproxEqAbs(threshold, totalSupply / 100, 1e16);
    }

    function test_timelock_delay_is_2_days() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPOSE → VOTE → QUEUE → EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_full_governance_lifecycle() public {
        // 1. Build a proposal: mint 1 000 tokens to carol via governance
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(govToken.mint, (carol, 1000e18));
        string memory description = "Proposal: mint 1000 PRED to carol";
        bytes32 descHash = keccak256(bytes(description));

        // deployer has > 1% supply and is self-delegated
        vm.prank(deployer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 2. Advance past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // 3. Vote (deployer votes For = 1)
        vm.prank(deployer);
        governor.castVote(proposalId, 1); // 1 = For

        // 4. Advance past voting period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        // 5. State should be Succeeded
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // 6. Queue in Timelock
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // 7. Advance past Timelock delay (2 days)
        vm.warp(block.timestamp + 2 days + 1);

        // 8. Execute
        uint256 carolBefore = govToken.balanceOf(carol);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(govToken.balanceOf(carol), carolBefore + 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                           DEFEATED PROPOSAL
    //////////////////////////////////////////////////////////////*/

    function test_proposal_defeated_if_quorum_not_met() public {
        // carol has 0 tokens so her vote won't meet quorum
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(govToken);
        calldatas[0] = abi.encodeCall(govToken.mint, (carol, 1e18));
        string memory description = "Low quorum proposal";

        // Give carol exactly 1 token so she can just barely propose
        // Actually deployer proposes (he has >1%)
        vm.prank(deployer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Only carol votes — but she has no power (no delegation)
        vm.prank(carol);
        governor.castVote(proposalId, 1);
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        // Should be Defeated (quorum not reached)
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function test_propose_below_threshold_reverts() public {
        // carol has no tokens → below 1% threshold
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(govToken);

        vm.expectRevert(); // GovernorInsufficientProposerVotes
        vm.prank(carol);
        governor.propose(targets, values, calldatas, "Should fail");
    }

    /*//////////////////////////////////////////////////////////////
                         TIMELOCK CONTROLS TREASURY
    //////////////////////////////////////////////////////////////*/

    function test_timelock_is_admin_of_gov_token() public view {
        assertTrue(govToken.hasRole(govToken.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    function test_only_timelock_can_mint_gov_token() public {
        vm.expectRevert();
        vm.prank(deployer);
        govToken.mint(carol, 1e18);
    }

    function test_clock_mode_matches_governor() public view {
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }
}
