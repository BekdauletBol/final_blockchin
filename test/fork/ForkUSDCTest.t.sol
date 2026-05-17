// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Fork test against Arbitrum mainnet USDC.
///         Run with: forge test --match-contract ForkUSDCTest --fork-url $ARBITRUM_RPC_URL -vvv
contract ForkUSDCTest is Test {
    using SafeERC20 for IERC20;

    // Arbitrum mainnet USDC (bridged)
    address internal constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    // USDC whale on Arbitrum
    address internal constant WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    IERC20 internal usdc;
    address internal alice = makeAddr("alice");

    function setUp() public {
        // Fork Arbitrum mainnet at a recent block
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        usdc = IERC20(USDC);
    }

    function test_fork_usdc_balance_readable() public view {
        uint256 whaleBalance = usdc.balanceOf(WHALE);
        console2.log("USDC whale balance:", whaleBalance);
        assertGt(whaleBalance, 0, "whale has no USDC");
    }

    function test_fork_usdc_transfer_from_whale() public {
        uint256 amount = 1000e6; // 1 000 USDC
        vm.prank(WHALE);
        usdc.safeTransfer(alice, amount);
        assertEq(usdc.balanceOf(alice), amount);
    }

    function test_fork_usdc_approve_and_transfer_from() public {
        uint256 amount = 500e6;
        vm.prank(WHALE);
        usdc.safeTransfer(alice, amount);
        vm.prank(alice);
        usdc.forceApprove(address(this), amount);
        usdc.safeTransferFrom(alice, address(this), amount);
        assertEq(usdc.balanceOf(address(this)), amount);
    }

    function test_fork_usdc_decimal_is_6() public view {
        // Verify the token we integrate with has 6 decimals as assumed throughout the protocol
        bytes memory data = abi.encodeWithSignature("decimals()");
        (bool ok, bytes memory ret) = USDC.staticcall(data);
        assertTrue(ok);
        uint8 dec = abi.decode(ret, (uint8));
        assertEq(dec, 6, "USDC decimals != 6");
    }

    function test_fork_usdc_totalSupply_positive() public view {
        assertGt(usdc.totalSupply(), 0);
    }
}
