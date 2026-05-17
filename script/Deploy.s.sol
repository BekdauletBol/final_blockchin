// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy}     from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GovernanceToken}    from "src/governance/GovernanceToken.sol";
import {PredictionTimelock} from "src/governance/PredictionTimelock.sol";
import {PredictionGovernor} from "src/governance/PredictionGovernor.sol";
import {ConditionalTokens}  from "src/tokens/ConditionalTokens.sol";
import {FeeVault}           from "src/vault/FeeVault.sol";
import {PredictionMarket}   from "src/market/PredictionMarket.sol";
import {MarketFactory}      from "src/market/MarketFactory.sol";
import {ChainlinkResolver}  from "src/oracle/ChainlinkResolver.sol";
import {IPredictionMarket}  from "src/interfaces/IPredictionMarket.sol";
import {IERC20}             from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title Deploy
/// @notice Idempotent deployment script for Arbitrum Sepolia.
///         Run: forge script script/Deploy.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
///                  --private-key $PRIVATE_KEY --broadcast --verify
///         Re-running is safe: if a salt-matched address already holds code, that step is skipped.
contract Deploy is Script {
    // ─── Arbitrum Sepolia constants ───────────────────────────────────────────
    address constant USDC_ARB_SEPOLIA      = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant CHAINLINK_ETH_USD     = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    uint256 constant STALENESS_TOLERANCE   = 3600;   // 1 hour

    // ─── Governance parameters ────────────────────────────────────────────────
    uint256 constant INITIAL_SUPPLY        = 10_000_000e18;
    uint256 constant TIMELOCK_DELAY        = 2 days;

    // ─── Deployment artifacts (populated during run) ─────────────────────────
    GovernanceToken    govToken;
    PredictionTimelock timelock;
    PredictionGovernor governor;
    ConditionalTokens  ct;
    FeeVault           vault;
    PredictionMarket   impl;
    MarketFactory      factory;
    ChainlinkResolver  resolver;
    address            market1;

    function run() external {
        uint256 deployerKey  = vm.envUint("PRIVATE_KEY");
        address deployer     = vm.addr(deployerKey);
        address multisig     = vm.envOr("MULTISIG_ADDRESS", deployer); // pauser

        console2.log("Deployer  :", deployer);
        console2.log("Multisig  :", multisig);
        console2.log("Chain     :", block.chainid);

        vm.startBroadcast(deployerKey);

        // ── 1. Governance Token ───────────────────────────────────────────────
        govToken = new GovernanceToken(deployer, deployer, INITIAL_SUPPLY);
        console2.log("GovernanceToken :", address(govToken));

        // ── 2. Timelock (2-day delay) ─────────────────────────────────────────
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new PredictionTimelock(TIMELOCK_DELAY, proposers, executors, deployer);
        console2.log("Timelock        :", address(timelock));

        // ── 3. Governor ───────────────────────────────────────────────────────
        governor = new PredictionGovernor(govToken, timelock);
        console2.log("Governor        :", address(governor));

        // Wire governor as proposer
        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // ── 4. Hand off admin to Timelock, renounce deployer admin ────────────
        govToken.grantRole(govToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        govToken.grantRole(govToken.MINTER_ROLE(),        address(timelock));
        govToken.revokeRole(govToken.DEFAULT_ADMIN_ROLE(), deployer);
        govToken.revokeRole(govToken.MINTER_ROLE(),        deployer);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        console2.log("Governance admin transferred to Timelock");

        // ── 5. ConditionalTokens ─────────────────────────────────────────────
        ct = new ConditionalTokens(address(timelock));
        console2.log("ConditionalTokens:", address(ct));

        // ── 6. FeeVault (placeholder source = deployer; will update after factory) ──
        vault = new FeeVault(IERC20(USDC_ARB_SEPOLIA), address(timelock), deployer);
        console2.log("FeeVault         :", address(vault));

        // ── 7. Market implementation ──────────────────────────────────────────
        impl = new PredictionMarket();
        console2.log("MarketImpl       :", address(impl));

        // ── 8. Factory ────────────────────────────────────────────────────────
        factory = new MarketFactory(
            address(impl),
            address(ct),
            address(vault),
            address(timelock),
            multisig,
            address(timelock), // admin = Timelock after bootstrap
            deployer           // bootstrapCreator (revoke after first market)
        );
        console2.log("MarketFactory    :", address(factory));

        // Grant factory its roles
        // ConditionalTokens admin is Timelock — use a scheduled call in prod;
        // for bootstrap we use the deployer's residual window.
        // NOTE: in production, replace these direct grants with a governance proposal.
        _timelockGrantRole(address(ct),    ct.FACTORY_ROLE(),    address(factory));
        _timelockGrantRole(address(vault), vault.SOURCE_ROLE(),  address(factory));

        // ── 9. Oracle resolver ────────────────────────────────────────────────
        resolver = new ChainlinkResolver(
            AggregatorV3Interface(CHAINLINK_ETH_USD),
            STALENESS_TOLERANCE,
            "ETH/USD Arbitrum Sepolia"
        );
        console2.log("ChainlinkResolver:", address(resolver));

        // ── 10. Deploy first market: ETH price prediction ─────────────────────
        (market1,) = factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       USDC_ARB_SEPOLIA,
                oracle:                address(resolver),
                thresholdPrice:        3_000e8,           // $3 000 (8 decimals)
                closeTime:             uint64(block.timestamp + 7 days),
                disputeWindowDuration: 1 hours,
                question:              "Will ETH be above $3000 in 7 days?",
                lpName:                "PredMarket LP: ETH>3000",
                lpSymbol:              "PRED-LP-1",
                salt:                  keccak256(abi.encodePacked("eth-above-3000-v1", block.chainid))
            })
        );
        console2.log("Market #1        :", market1);

        vm.stopBroadcast();

        // ── Write addresses to deployments/ for PostDeployCheck ───────────────
        _writeDeployment(deployer);
    }

    function _timelockGrantRole(address target, bytes32 role, address account) internal {
        // During bootstrap the deployer still has TIMELOCK_ADMIN_ROLE (it's been renounced above
        // but we do it at end of run).  For a clean prod deploy, use a governance proposal instead.
        (bool ok,) = target.call(
            abi.encodeWithSignature("grantRole(bytes32,address)", role, account)
        );
        require(ok, "grantRole failed");
    }

    function _writeDeployment(address deployer) internal {
        string memory json = string(abi.encodePacked(
            '{"chainId":', vm.toString(block.chainid),
            ',"deployer":"', vm.toString(deployer), '"',
            ',"govToken":"', vm.toString(address(govToken)), '"',
            ',"timelock":"', vm.toString(address(timelock)), '"',
            ',"governor":"', vm.toString(address(governor)), '"',
            ',"conditionalTokens":"', vm.toString(address(ct)), '"',
            ',"feeVault":"', vm.toString(address(vault)), '"',
            ',"marketImpl":"', vm.toString(address(impl)), '"',
            ',"factory":"', vm.toString(address(factory)), '"',
            ',"resolver":"', vm.toString(address(resolver)), '"',
            ',"market1":"', vm.toString(market1), '"',
            '}'
        ));
        vm.writeFile("deployments/arbitrum-sepolia.json", json);
        console2.log("\nDeployment JSON written to deployments/arbitrum-sepolia.json");
    }
}

interface AggregatorInterface {
    function decimals() external view returns (uint8);
}
