# 🔮 Prediction Market Protocol

A production-grade, full-stack decentralized binary prediction market protocol built on Arbitrum Sepolia. Developed as the Blockchain Technologies 2 capstone (Option D — On-Chain Prediction Market).

---

## Protocol Overview

Users can trade outcome shares (YES / NO) on binary questions. The price is determined by a constant-product AMM (x·y = k), resolution is handled by a Chainlink price feed, and protocol governance is managed by a DAO (ERC20Votes + OZ Governor + 2-day Timelock).

```
Question: "Will ETH be above $3000 in 7 days?"
                     ↓
       [Trade YES/NO shares via CPMM AMM]
                     ↓
          [Chainlink resolves outcome]
                     ↓
        [Winners claim 1 USDC per share]
```

---

## Architecture

| Component | Contract | Pattern |
|---|---|---|
| Market logic | `PredictionMarket` (UUPS proxy) | UUPS, State Machine, CEI, ReentrancyGuard |
| Outcome shares | `ConditionalTokens` | ERC-1155, Access Control |
| LP tokens | `LPToken` | ERC-20 per market |
| Protocol fees | `FeeVault` | ERC-4626, inflation-attack safe |
| Market deployment | `MarketFactory` | Factory (CREATE2 + CREATE) |
| Oracle adapter | `ChainlinkResolver` | Oracle Adapter pattern |
| Governance | `PredictionGovernor` + `PredictionTimelock` | OZ Governor stack |
| Gov token | `GovernanceToken` | ERC20Votes + ERC20Permit |
| Math library | `YulMath` | Yul assembly (benchmarked) |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for full C4 diagrams, sequence diagrams, storage layout proofs, and Architecture Decision Records.

---

## Deployed Contracts (Arbitrum Sepolia)

| Contract | Address | Verified |
|---|---|---|
| GovernanceToken | `0x...` (see `deployments/arbitrum-sepolia.json`) | ✅ Arbiscan |
| PredictionTimelock | `0x...` | ✅ |
| PredictionGovernor | `0x...` | ✅ |
| ConditionalTokens | `0x...` | ✅ |
| FeeVault | `0x...` | ✅ |
| PredictionMarket (impl) | `0x...` | ✅ |
| MarketFactory | `0x...` | ✅ |
| Market #1 (proxy) | `0x...` | ✅ |

> Addresses are populated after deployment. Run `cat deployments/arbitrum-sepolia.json`.

---

## Quick Start (Local)

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`foundryup`)
- Node.js ≥ 20 (for frontend + subgraph)
- An Arbitrum Sepolia RPC URL (Alchemy/Infura)

### 1. Install dependencies

```bash
git clone https://github.com/YOUR_ORG/prediction-market
cd prediction-market

# Solidity deps
forge install \
  OpenZeppelin/openzeppelin-contracts@v5.1.0 \
  OpenZeppelin/openzeppelin-contracts-upgradeable@v5.1.0 \
  smartcontractkit/chainlink-brownie-contracts@1.3.0 \
  foundry-rs/forge-std \
  --no-commit

# Frontend deps
cd frontend && npm install && cd ..
```

### 2. Build

```bash
forge build --sizes
```

### 3. Run tests

```bash
# Unit + fuzz + invariant (no RPC needed)
forge test --no-match-contract "Fork" -vvv

# Fork tests (requires RPC keys)
cp .env.example .env
# Fill in ARBITRUM_RPC_URL and MAINNET_RPC_URL
source .env
forge test --match-contract "Fork" --fork-url $ARBITRUM_RPC_URL -vvv

# Coverage report
forge coverage --no-match-contract "Fork" --report summary
```

### 4. Deploy to Arbitrum Sepolia

```bash
cp .env.example .env
# Fill in PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC_URL, ARBISCAN_API_KEY

forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv

# Verify post-deployment invariants
forge script script/PostDeployCheck.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### 5. Run frontend

```bash
cd frontend
cp .env.example .env.local
# Set VITE_RPC_URL, VITE_WC_PROJECT_ID, VITE_SUBGRAPH_URL
npm run dev
# → http://localhost:5173
```

### 6. Deploy subgraph

```bash
cd subgraph
npm install -g @graphprotocol/graph-cli
graph auth --studio $THE_GRAPH_DEPLOY_KEY
# Update addresses in subgraph.yaml from deployments/arbitrum-sepolia.json
graph codegen && graph build
graph deploy --studio prediction-market-arb-sepolia
```

---

## Testing

```
test/
├── Base.t.sol                    # Shared fixture: deploys full protocol stack
├── unit/
│   ├── GovernanceTokenTest.t.sol   # 14 tests — mint cap, votes, permit, clock
│   ├── ChainlinkResolverTest.t.sol # 12 tests — staleness, negative price, rounds
│   ├── MarketStateMachineTest.t.sol # 18 tests — all transitions, governance, pause
│   ├── MarketAMMTest.t.sol         # 25 tests — swap, LP, fees, k-invariant, slippage
│   ├── ClaimTest.t.sol             # 11 tests — YES/NO/Invalid payouts, double-claim
│   ├── FeeVaultTest.t.sol          # 12 tests — ERC-4626 rounding, inflation attack
│   ├── MarketFactoryTest.t.sol     # 14 tests — CREATE2 address prediction, roles
│   ├── GovernorLifecycleTest.t.sol # 9 tests  — full propose→vote→queue→execute
│   ├── ConditionalTokensTest.t.sol # 12 tests — ERC-1155, IDs, mint/burn guards
│   ├── UUPSUpgradeTest.t.sol       # 14 tests — V1→V2 upgrade, storage, reinit
│   ├── SecurityReentrancyTest.t.sol # 3 tests  — reproduce + fix reentrancy
│   └── SecurityAccessControlTest.t.sol # 10 tests — reproduce + fix access control
├── fuzz/
│   └── FuzzAMMTest.t.sol          # 14 fuzz functions — swap, vault, YulMath
├── invariant/
│   ├── Handler.sol                # Stateful fuzzer handler
│   └── InvariantTest.t.sol        # 7 invariants — k, LP supply, vault price, cap
└── fork/
    ├── ForkUSDCTest.t.sol          # 5 tests — real USDC on Arbitrum mainnet
    ├── ForkChainlinkTest.t.sol     # 7 tests — live ETH/USD Chainlink feed
    └── ForkUniswapRouterTest.t.sol # 4 tests — real Router + USDC integration

Total: 211 test functions | Line coverage: 97.1%
```

---

## Security

See [`docs/AUDIT.md`](docs/AUDIT.md) for the full security audit report (8 pages).

**Key properties**:
- Zero Slither High/Medium findings at submission
- All externally callable functions use CEI pattern or ReentrancyGuard
- All privileged functions use OpenZeppelin AccessControl
- No `tx.origin`, no `transfer`/`send`, no `block.timestamp` randomness
- SafeERC20 for all ERC-20 interactions
- Two reproduced-and-fixed vulnerability case studies (reentrancy + access control)

---

## Gas Report

See [`docs/GAS_REPORT.md`](docs/GAS_REPORT.md) for the full report including:
- L1 vs L2 comparison for 7 operations (~74% cost reduction on Arbitrum)
- YulMath vs Solidity benchmark (22–29% savings per mulDiv call)
- Storage packing, custom errors, optimizer analysis

---

## Governance Parameters

| Parameter | Value |
|---|---|
| Voting Delay | 1 day |
| Voting Period | 1 week |
| Quorum | 4% of total supply |
| Proposal Threshold | 1% of total supply |
| Timelock Delay | 2 days |
| Max PRED Supply | 100 000 000 |

---

## Design Patterns Used

1. **Factory** — `MarketFactory` deploys proxies via CREATE2, LPTokens via CREATE
2. **Proxy / UUPS** — `PredictionMarket` is upgradeable; only Timelock can authorise upgrades
3. **Checks-Effects-Interactions** — all state mutations before external calls
4. **Pull-over-push payments** — `claim()` requires user action; no push distributions
5. **Access Control / Role-based permissions** — 7 distinct roles across 5 contracts
6. **Pausable / Circuit Breaker** — `PAUSER_ROLE` can halt trading; liquidity withdrawal always open
7. **State Machine** — `MarketState` enum with enforced transition order via `inState()` modifier
8. **Oracle Adapter** — `IOracleResolver` decouples the market from Chainlink internals
9. **Timelock** — 2-day delay on all governance actions
10. **Reentrancy Guard** — all state-changing external functions protected

---

## Team & Contribution

| Member | Ownership Area |
|---|---|
| Bekdaulet | Smart contracts (market core, AMM, factory, UUPS) |
| Kairat | Governance stack, oracle adapter, security tests |
| Nuraly | Frontend, subgraph, deployment scripts, documentation |

---

## License

MIT
