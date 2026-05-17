# Architecture & Design Document
**Prediction Market Protocol — On-Chain Binary Outcome Markets**
Version 1.0 | Course: Blockchain Technologies 2 | Option D

---

## 1. System Context (C4 Level 1)

```
┌─────────────────────────────────────────────────────────────────┐
│                         EXTERNAL USERS                          │
│   Trader (buys YES/NO)  │  LP (adds liquidity)  │  DAO Voter   │
└────────────┬────────────┴──────────┬────────────┴──────┬────────┘
             │                       │                   │
             ▼                       ▼                   ▼
    ┌─────────────────────────────────────────────────────────┐
    │              Prediction Market dApp (React)             │
    │     Wagmi + Viem  ◄──► The Graph subgraph (indexer)    │
    └──────────────────────────────┬──────────────────────────┘
                                   │ RPC / Events
                                   ▼
    ┌─────────────────────────────────────────────────────────┐
    │              Arbitrum Sepolia L2 (EVM)                  │
    │   [MarketFactory]  [PredictionMarket×N]  [FeeVault]     │
    │   [GovernanceToken]  [Governor]  [Timelock]             │
    │   [ConditionalTokens ERC-1155]                          │
    └──────────────────────────────┬──────────────────────────┘
                                   │
             ┌─────────────────────┤
             │                     │
             ▼                     ▼
    ┌──────────────────┐  ┌──────────────────────┐
    │  Chainlink Feeds │  │  Arbitrum Bridge      │
    │  (ETH/USD etc.)  │  │  (L1↔L2 messaging)   │
    └──────────────────┘  └──────────────────────┘
```

---

## 2. Container / Component Diagram (C4 Level 2)

```
┌─────────────────────── Protocol Contracts ─────────────────────────────────┐
│                                                                              │
│  ┌──────────────────┐    creates (CREATE2)   ┌──────────────────────────┐  │
│  │  MarketFactory   │──────────────────────► │  PredictionMarket (UUPS) │  │
│  │  CREATOR_ROLE    │    creates (CREATE)    │  one proxy per market    │  │
│  │  owned by TL     │──────────────────────► │  yesReserve / noReserve  │  │
│  └────────┬─────────┘                        │  state machine (5 states)│  │
│           │ grantRole(FACTORY_ROLE)           └──────────┬───────────────┘  │
│           ▼                                              │                  │
│  ┌──────────────────┐    mint/burn                       │ notifyFee        │
│  │ ConditionalTokens│◄──────────────────────────────────┤                  │
│  │   ERC-1155       │    mintComplete/burnSingle         │ SafeTransferFrom  │
│  └──────────────────┘                                    ▼                  │
│                                              ┌──────────────────────────┐  │
│  ┌──────────────────┐                        │       FeeVault           │  │
│  │  GovernanceToken │                        │   ERC-4626 (USDC)        │  │
│  │  ERC20Votes      │                        │   SOURCE_ROLE = factory  │  │
│  │  ERC20Permit     │                        └──────────────────────────┘  │
│  └────────┬─────────┘                                                       │
│           │ token()                                                          │
│           ▼                                                                  │
│  ┌──────────────────┐  2-day queue    ┌──────────────────────────────────┐ │
│  │  PredictionGov.  │───────────────► │      PredictionTimelock          │ │
│  │  OZ Governor     │                 │   controls: MarketFactory admin  │ │
│  │  1d/7d/4%/1%     │◄────────────────│             FeeVault admin       │ │
│  └──────────────────┘  PROPOSER_ROLE  │             GovToken mint        │ │
│                                       └──────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────┐                                    │
│  │        ChainlinkResolver             │  ← Oracle Adapter pattern         │
│  │  wraps AggregatorV3Interface         │    Market calls IOracleResolver   │
│  │  staleness check (≤ N seconds)       │    not Chainlink directly         │
│  └─────────────────────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Access-Control Role Map

| Role | Holder | Controls |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` (Timelock) | `PredictionTimelock` | All admin functions across all contracts |
| `PROPOSER_ROLE` (Timelock) | `PredictionGovernor` | Only the Governor can propose to Timelock |
| `MINTER_ROLE` (GovToken) | `PredictionTimelock` | Only governance can mint new PRED |
| `FACTORY_ROLE` (CT) | `MarketFactory` | Only factory can register new conditions |
| `SOURCE_ROLE` (Vault) | `MarketFactory` | Markets forwarded fees; extensible via governance |
| `CREATOR_ROLE` (Factory) | `PredictionTimelock` + deployer (bootstrap) | Deploys new markets |
| `UPGRADER_ROLE` (Market) | `PredictionTimelock` | UUPS implementation pointer |
| `PAUSER_ROLE` (Market) | multisig | Emergency halt of trading |

---

## 3. Sequence Diagrams

### 3.1 Trade: buyYes

```
Trader          USDC           PredictionMarket      ConditionalTokens     FeeVault
  │                                    │                     │                  │
  │── approve(market, amt) ──────────► │                     │                  │
  │── buyYes(amt, minOut, deadline) ──► │                     │                  │
  │                              [CHECKS]                                        │
  │                              deadline OK, not frozen, not paused             │
  │                              [EFFECTS]                                        │
  │                              compute feeProtocol, feeLP, sharesOut           │
  │                              update yesReserve, noReserve, accLPFees         │
  │                              verify kAfter >= kBefore                         │
  │                              [INTERACTIONS]                                   │
  │                                    │── safeTransferFrom(trader, this) ──►    │
  │                                    │── mintComplete(this, effectiveAmt) ──►  │
  │                                    │                     │ mint YES+NO shares │
  │                                    │◄─────────────────── │                  │
  │                                    │── safeTransferFrom(this, trader, YES) ─►│
  │                                    │── safeIncreaseAllowance(vault, fee) ──► │
  │                                    │── notifyFee(fee) ──────────────────────►│
  │                                    │                                   safeTransferFrom
  │◄── Swap event ──────────────────── │                     │                  │
```

### 3.2 Governance: propose → vote → queue → execute

```
Proposer          Governor           Timelock          Target Contract
   │                  │                  │                   │
   │── propose(...) ──►│                  │                   │
   │◄─ proposalId ─── │                  │                   │
   │                  │                  │                   │
   [1 day voting delay warp]
   │                  │                  │                   │
   │── castVote(id,1) ►│                  │                   │
   │                  │                  │                   │
   [1 week voting period warp + quorum met]
   │                  │                  │                   │
   │── queue(…) ─────►│── scheduleBatch─►│                   │
   │                  │                  │                   │
   [2 day timelock delay warp]
   │                  │                  │                   │
   │── execute(…) ───►│── executeBatch ─►│── call(data) ────►│
   │                  │                  │   mint / param set │
```

### 3.3 Resolution: Closed → Finalized (happy path)

```
Anyone         PredictionMarket    ChainlinkResolver    Winner
  │                  │                   │                 │
  │── close() ──────►│  [check timestamp] │                 │
  │                  │ ammFrozen = true   │                 │
  │── resolve() ─────►│                   │                 │
  │                  │── latestPrice() ──►│                 │
  │                  │◄─ (price, ts) ─── │                 │
  │                  │ staleness check OK  │                 │
  │                  │ outcome = Yes/No    │                 │
  │                  │ disputeWindowEnd = now + 1h           │
  [1 hour dispute window elapses — no dispute]
  │── finalize() ───►│  state = Finalized │                 │
  │                  │                   │                 │
  │                  │                   │  ── claim() ───►│
  │                  │                   │  burn YES shares │
  │                  │                   │  transfer USDC ─►│
```

---

## 4. Storage Layout (Upgradeable Contracts)

### PredictionMarket V1 → V2 Proof of No Collision

Solidity storage layout is sequential. UUPS proxy delegates all calls to the implementation; the proxy's own storage is ERC-1967 reserved slots.

| Slot | Variable | Type | V1 | V2 |
|---|---|---|---|---|
| 0–49 | OZ `Initializable`, `AccessControl`, `Pausable`, `ReentrancyGuard`, `UUPSUpgradeable` gaps | various | inherited | inherited (unchanged) |
| 50 | `collateralToken` | address | ✅ | ✅ same |
| 51 | `conditionalTokens` | address | ✅ | ✅ same |
| 52 | `oracle` | address | ✅ | ✅ same |
| 53 | `feeVault` | address | ✅ | ✅ same |
| 54 | `lpToken` | address | ✅ | ✅ same |
| 55 | `thresholdPrice` | int256 | ✅ | ✅ same |
| 56 | `yesTokenId` | uint256 | ✅ | ✅ same |
| 57 | `noTokenId` | uint256 | ✅ | ✅ same |
| 58 | `closeTime` | uint64 | ✅ | ✅ same |
| 59 | `resolutionTime` | uint64 | ✅ | ✅ same |
| 60 | `disputeWindowDuration` | uint64 | ✅ | ✅ same |
| 61 | `question` | string | ✅ | ✅ same |
| 62 | `marketState` | MarketState (uint8) | ✅ | ✅ same |
| 63 | `marketOutcome` | Outcome (uint8) | ✅ | ✅ same |
| 64 | `disputeWindowEnd` | uint64 | ✅ | ✅ same |
| 65 | `yesReserve` | uint256 | ✅ | ✅ same |
| 66 | `noReserve` | uint256 | ✅ | ✅ same |
| 67 | `accumulatedLPFees` | uint256 | ✅ | ✅ same |
| 68 | `ammFrozen` | bool | ✅ | ✅ same |
| 69–108 | `__gap[40]` (V1) | uint256[40] | ✅ | slots 69-71 consumed by V2 vars |
| 69 | `cumulativeVolume` | uint256 | (gap) | ✅ V2 new |
| 70 | `uniqueTraders` | uint256 | (gap) | ✅ V2 new |
| 71 | `hasTraded` | mapping | (gap) | ✅ V2 new |

**Conclusion**: V2 consumes 3 of 40 gap slots. No collision possible with V1 state. ✓

---

## 5. Trust Assumptions

### Who can do what

| Actor | Power | Risk if compromised |
|---|---|---|
| **PredictionTimelock** | Mints PRED, deploys markets, upgrades implementations, governs FeeVault | Highest risk — is the DAO treasury. Protected by 2-day delay and governance quorum. |
| **PredictionGovernor** | Schedules Timelock proposals | Governance attack vector. Protected by 1% proposal threshold, 4% quorum, 1-week voting. |
| **multisig (pauser)** | Pauses trading only | Limited damage: traders cannot trade but can still remove liquidity (intentionally unpaused). Cannot steal funds. |
| **ChainlinkResolver** | Reports price used for outcome | If feed is compromised, outcome could be forced. Mitigated by: dispute window + governance override path. |
| **MarketFactory.CREATOR_ROLE** | Deploys new markets | Could deploy malicious markets. Mitigated by Timelock holding CREATOR_ROLE in production. |
| **UUPS Upgrader** | Points implementation pointer | Can brick or backdoor all markets sharing that implementation. Only Timelock holds UPGRADER_ROLE. |

### What happens if the multisig is compromised?

The multisig holds only `PAUSER_ROLE`. The attacker can pause trading, blocking swaps — but:
- Liquidity providers can still call `removeLiquidity` (not gated by Pausable by design).
- Claim is also not gated — finalized winners can still collect.
- The attacker cannot steal funds, upgrade contracts, or change resolution outcomes.
- Governance (Timelock) can revoke PAUSER_ROLE from the compromised multisig.

---

## 6. Design Decision Log (ADRs)

### ADR-001: Timestamp Clock (vs Block Number Clock)
**Context**: OZ Governor + ERC20Votes can use block numbers (default pre-v5) or timestamps (EIP-6372).  
**Options**: Block number (predictable but non-linear on Arbitrum); Timestamp (continuous, matches human spec: "1 day delay", "1 week voting").  
**Decision**: Timestamp clock (`mode=timestamp`) in both GovernanceToken and PredictionGovernor.  
**Consequences**: Slightly less Sybil-resistant than block numbers (no mempool ordering guarantee), but Arbitrum block production is controlled by sequencer making block-number games possible anyway. Human-readable parameters are more auditable.

### ADR-002: CPMM (vs LMSR) for AMM Pricing
**Context**: Prediction markets can use LMSR (subsidized market maker) or CPMM (constant-product, like Uniswap V2).  
**Options**: LMSR — theoretically optimal, self-contained loss; CPMM — simpler, battle-tested, integrates cleanly with LP tokens.  
**Decision**: CPMM (x·y = k) with 0.3% fee split 0.25% LP / 0.05% protocol.  
**Consequences**: CPMM can have higher price impact on skewed pools; counterparty is the LP not the market maker. This is acceptable given the educational context and simpler auditing surface.

### ADR-003: Single Shared ConditionalTokens Contract
**Context**: Could deploy one ERC-1155 per market, or one shared ERC-1155 for all markets.  
**Options**: Per-market ERC-1155 (isolated but creates many contracts); Shared ERC-1155 (one contract, ID namespace partitioned by market address).  
**Decision**: Single shared ConditionalTokens using `keccak256(market, outcomeIndex)` as token ID.  
**Consequences**: Simpler for wallets and explorers. Risk: a bug in ConditionalTokens affects all markets. Mitigated by: ConditionalTokens admin is Timelock, fully audited separately.

### ADR-004: Pull-over-Push for Winnings
**Context**: After finalization, distribute winnings automatically vs require user to call `claim()`.  
**Options**: Push (auto-distribute on finalize — O(n) gas, DoS vector); Pull (user calls claim, O(1) per user).  
**Decision**: Pull-over-push: `claim()` burns winning shares and transfers collateral.  
**Consequences**: Users must actively claim. No DoS risk. Standard DeFi UX.

### ADR-005: Oracle Adapter Pattern
**Context**: Markets need price resolution. Hardcoding Chainlink would lock out UMA, Pyth, etc.  
**Options**: Hardcode Chainlink; abstract via `IOracleResolver`.  
**Decision**: `IOracleResolver` interface with `ChainlinkResolver` concrete implementation and `MockResolver` for tests.  
**Consequences**: Future markets can use different oracle providers without changing PredictionMarket. Slither can see that the oracle call is an external call — documented in audit.

### ADR-006: FeeVault ERC-4626 with _decimalsOffset = 6
**Context**: First depositor inflation attack: attacker can donate assets to manipulate share price.  
**Options**: MINIMUM_LIQUIDITY lock (Uniswap V2 style); Virtual shares offset (OZ v5 style).  
**Decision**: OZ v5 `_decimalsOffset() = 6`. An attacker would need to donate 10^6× the victim's deposit to move the price per share by 1 unit — economically infeasible.  
**Consequences**: Share amounts are ~1M× larger than asset amounts, slightly confusing for off-chain tooling. Documented in README.

### ADR-007: Dispute Window 1 Hour (testnet) vs 48 Hours (mainnet)
**Context**: Spec says "dispute window" — no fixed duration specified.  
**Options**: Short window (faster UX); Long window (more time to detect manipulation).  
**Decision**: Configurable per-market via `disputeWindowDuration` param (constructor); deploy script uses 1h for testnet, 48h recommended for mainnet.  
**Consequences**: Governance can deploy markets with appropriate windows for their oracle and use case.

---

## 7. Gas Optimisation Strategy

- **YulMath.mulDiv**: replaces intermediate SafeMath with a 512-bit phantom-overflow-safe algorithm. Saves ~30% gas on every swap quote computation vs naïve `(a * b) / c`.
- **Custom errors** throughout (vs revert strings): saves ~200–500 gas per revert.
- **`uint64` for timestamps**: closeTime, resolutionTime, disputeWindowEnd stored as uint64 (not uint256), packed into the same slot with the enum values — 1 fewer SSTORE/SLOAD.
- **`accumulatedLPFees` in single slot**: LP fee tracking is a single uint256 rather than a per-LP mapping. LPs redeem their pro-rata share at removeLiquidity time using mulDiv.
- **Optimizer runs = 200**: balances deploy cost vs call cost. Deployment is a one-time cost; calls are repeated by users.
- **`via_ir = false`**: faster compile; IR pipeline not needed at this optimizer run count.

See `docs/GAS_REPORT.md` for numeric before/after benchmarks.
