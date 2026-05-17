// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson}           from "forge-std/StdJson.sol";

import {GovernanceToken}    from "src/governance/GovernanceToken.sol";
import {PredictionTimelock} from "src/governance/PredictionTimelock.sol";
import {PredictionGovernor} from "src/governance/PredictionGovernor.sol";
import {ConditionalTokens}  from "src/tokens/ConditionalTokens.sol";
import {FeeVault}           from "src/vault/FeeVault.sol";
import {PredictionMarket}   from "src/market/PredictionMarket.sol";
import {MarketFactory}      from "src/market/MarketFactory.sol";

/// @title PostDeployCheck
/// @notice Verifies post-deployment invariants for the Prediction Market protocol.
///         Run: forge script script/PostDeployCheck.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
///         Exit code 0 = all checks pass. Non-zero = at least one check failed.
///         Output is checked into the repo as docs/POST_DEPLOY_CHECK_OUTPUT.txt
contract PostDeployCheck is Script {
    using stdJson for string;

    uint256 failures;

    function run() external {
        string memory json = vm.readFile("deployments/arbitrum-sepolia.json");

        address govTokenAddr  = json.readAddress(".govToken");
        address timelockAddr  = json.readAddress(".timelock");
        address governorAddr  = json.readAddress(".governor");
        address ctAddr        = json.readAddress(".conditionalTokens");
        address vaultAddr     = json.readAddress(".feeVault");
        address implAddr      = json.readAddress(".marketImpl");
        address factoryAddr   = json.readAddress(".factory");
        address market1Addr   = json.readAddress(".market1");

        console2.log("==========================================================");
        console2.log(unicode"   POST-DEPLOYMENT VERIFICATION — Arbitrum Sepolia");
        console2.log("==========================================================\n");

        GovernanceToken    govToken  = GovernanceToken(govTokenAddr);
        PredictionTimelock timelock  = PredictionTimelock(payable(timelockAddr));
        PredictionGovernor governor  = PredictionGovernor(payable(governorAddr));
        ConditionalTokens  ct        = ConditionalTokens(ctAddr);
        FeeVault           vault     = FeeVault(vaultAddr);
        PredictionMarket   market    = PredictionMarket(market1Addr);

        // ── GOVERNANCE TOKEN ──────────────────────────────────────────────────
        _section("GovernanceToken");
        _check("Timelock has DEFAULT_ADMIN_ROLE",
            govToken.hasRole(govToken.DEFAULT_ADMIN_ROLE(), timelockAddr));
        _check("Timelock has MINTER_ROLE",
            govToken.hasRole(govToken.MINTER_ROLE(), timelockAddr));
        _check("Deployer does NOT have DEFAULT_ADMIN_ROLE",
            !govToken.hasRole(govToken.DEFAULT_ADMIN_ROLE(), json.readAddress(".deployer")));
        _check("totalSupply <= MAX_SUPPLY",
            govToken.totalSupply() <= govToken.MAX_SUPPLY());
        _check("CLOCK_MODE is timestamp",
            keccak256(bytes(govToken.CLOCK_MODE())) == keccak256(bytes("mode=timestamp")));

        // ── TIMELOCK ──────────────────────────────────────────────────────────
        _section("PredictionTimelock");
        _check("minDelay == 2 days",
            timelock.getMinDelay() == 2 days);
        _check("REQUIRED_MIN_DELAY == 2 days (constant)",
            timelock.REQUIRED_MIN_DELAY() == 2 days);
        _check("Governor has PROPOSER_ROLE",
            timelock.hasRole(timelock.PROPOSER_ROLE(), governorAddr));
        _check("Governor has CANCELLER_ROLE",
            timelock.hasRole(timelock.CANCELLER_ROLE(), governorAddr));
        _check("address(0) has EXECUTOR_ROLE (open execution)",
            timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        _check("Deployer does NOT have TIMELOCK_ADMIN_ROLE",
            !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), json.readAddress(".deployer")));

        // ── GOVERNOR ─────────────────────────────────────────────────────────
        _section("PredictionGovernor");
        _check("votingDelay == 1 day",
            governor.votingDelay() == 1 days);
        _check("votingPeriod == 1 week",
            governor.votingPeriod() == 1 weeks);
        _check("quorumNumerator == 4",
            governor.quorumNumerator() == 4);
        _check("CLOCK_MODE is timestamp",
            keccak256(bytes(governor.CLOCK_MODE())) == keccak256(bytes("mode=timestamp")));
        _check("Timelock is the governor's timelock",
            address(governor.timelock()) == timelockAddr);

        // ── CONDITIONAL TOKENS ────────────────────────────────────────────────
        _section("ConditionalTokens");
        _check("Timelock has DEFAULT_ADMIN_ROLE",
            ct.hasRole(ct.DEFAULT_ADMIN_ROLE(), timelockAddr));
        _check("Factory has FACTORY_ROLE",
            ct.hasRole(ct.FACTORY_ROLE(), factoryAddr));
        _check("Market1 is authorized",
            ct.isAuthorizedMarket(market1Addr));

        // ── FEE VAULT ─────────────────────────────────────────────────────────
        _section("FeeVault");
        _check("Timelock has DEFAULT_ADMIN_ROLE",
            vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), timelockAddr));
        _check("Factory has SOURCE_ROLE",
            vault.hasRole(vault.SOURCE_ROLE(), factoryAddr));

        // ── MARKET FACTORY ────────────────────────────────────────────────────
        _section("MarketFactory");
        _check("Implementation matches deployed impl",
            MarketFactory(factoryAddr).implementation() == implAddr);
        _check("Timelock has CREATOR_ROLE",
            MarketFactory(factoryAddr).hasRole(
                MarketFactory(factoryAddr).CREATOR_ROLE(), timelockAddr));
        _check("allMarketsLength == 1",
            MarketFactory(factoryAddr).allMarketsLength() == 1);

        // ── MARKET #1 ─────────────────────────────────────────────────────────
        _section("PredictionMarket #1");
        _check("Timelock has DEFAULT_ADMIN_ROLE",
            market.hasRole(market.DEFAULT_ADMIN_ROLE(), timelockAddr));
        _check("Timelock has UPGRADER_ROLE",
            market.hasRole(market.UPGRADER_ROLE(), timelockAddr));
        _check("Deployer does NOT have DEFAULT_ADMIN_ROLE on market",
            !market.hasRole(market.DEFAULT_ADMIN_ROLE(), json.readAddress(".deployer")));
        _check("AMM NOT frozen at launch",
            !market.ammFrozen());
        _check("Market state == Active (0)",
            uint8(market.state()) == 0);
        _check("closeTime > now",
            market.closeTime() > uint64(block.timestamp));

        // ── SUMMARY ──────────────────────────────────────────────────────────
        console2.log("\n==========================================================");
        if (failures == 0) {
            console2.log(unicode"   ALL CHECKS PASSED ✓");
        } else {
            console2.log("   FAILURES:", failures);
        }
        console2.log("==========================================================");

        require(failures == 0, "PostDeployCheck: one or more checks failed");
    }

    function _section(string memory name) internal pure {
        console2.log(string(abi.encodePacked("\n[ ", name, " ]")));
    }

    function _check(string memory label, bool condition) internal {
        if (condition) {
            console2.log(string(abi.encodePacked("  [PASS] ", label)));
        } else {
            console2.log(string(abi.encodePacked("  [FAIL] ", label)));
            failures++;
        }
    }
}
