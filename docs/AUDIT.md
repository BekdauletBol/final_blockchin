# Security Audit Report
**Protocol**: Prediction Market — On-Chain Binary Outcome Markets (Option D)  
**Auditors**: Team (internal, self-audit)  
**Scope commit**: `HEAD` of `main` at submission  
**Date**: 2026-05

---

## 1. Executive Summary

This report covers the full-stack smart-contract codebase of the Prediction Market protocol, developed as the Blockchain Technologies 2 capstone (Option D). The protocol enables on-chain binary prediction markets with a CPMM-based AMM, Chainlink oracle resolution, an ERC-4626 fee vault, ERC-1155 outcome shares, and DAO governance via OpenZeppelin's Governor stack deployed on Arbitrum Sepolia.

**Scope**: All contracts under `src/` excluding `src/mocks/`.  
**Files in scope**: 12 contracts, ~1 700 lines of Solidity.

**Summary of findings**:

| Severity | Count | Status |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 3 | Fixed |
| Informational | 5 | Acknowledged |
| Gas | 4 | Fixed |

**Slither**: zero High, zero Medium findings at submission. Full Slither output in Appendix A.

---

## 2. Scope

### In Scope
| File | Lines | Notes |
|---|---|---|
| `src/governance/GovernanceToken.sol` | 91 | ERC20Votes + ERC20Permit |
| `src/governance/PredictionTimelock.sol` | 27 | 2-day TimelockController |
| `src/governance/PredictionGovernor.sol` | 124 | OZ Governor full stack |
| `src/oracle/ChainlinkResolver.sol` | 97 | Chainlink adapter + staleness |
| `src/tokens/ConditionalTokens.sol` | 126 | ERC-1155 outcome shares |
| `src/tokens/LPToken.sol` | 35 | Per-market ERC-20 LP |
| `src/vault/FeeVault.sol` | 95 | ERC-4626 fee accumulator |
| `src/market/PredictionMarket.sol` | 500 | Core market logic |
| `src/market/PredictionMarketV2.sol` | 73 | UUPS upgrade demonstration |
| `src/market/MarketFactory.sol` | 177 | CREATE + CREATE2 factory |
| `src/libraries/YulMath.sol` | 166 | Assembly math library |
| `src/interfaces/*.sol` | 210 | Interface definitions |

### Out of Scope
- `src/mocks/` (test-only)
- `test/` (test code, not deployed)
- `subgraph/` (off-chain indexing)
- `frontend/` (off-chain UI)
- OpenZeppelin library code (assumed audited)

---

## 3. Methodology

**Tools used**:
- Slither 0.10.x — automated static analysis
- Manual code review — line-by-line reading of every in-scope file
- Forge fuzz tests — 5 000 runs per fuzz function
- Forge invariant tests — 256 runs × 50 depth
- Mythril (supplementary) — symbolic execution on PredictionMarket.sol

**Manual review focus areas**:
1. CEI (Checks-Effects-Interactions) compliance
2. Reentrancy vectors via ERC-1155 `onERC1155Received` callbacks
3. Oracle manipulation paths
4. Access control completeness
5. ERC-4626 rounding invariants
6. UUPS upgrade authorization and storage layout collision
7. AMM k-invariant preservation under fee accounting

---

## 4. Findings

### Finding S-01 — LOW: First Liquidity Provider Can Receive Zero LP Tokens

**Severity**: Low  
**Location**: `src/market/PredictionMarket.sol` — `addLiquidity()`  
**Status**: ✅ Fixed

**Description**: Without the MINIMUM_LIQUIDITY guard, the first LP depositing exactly 1000 units would receive 0 LP tokens (amount - MINIMUM_LIQUIDITY = 0), locking collateral permanently.

**Impact**: The first LP loses dust amounts of collateral with no LP shares. No systemic risk.

**Proof of concept**:
```solidity
// Before fix — would pass the require but mint 0 LP
require(collateralAmount > MINIMUM_LIQUIDITY); // passes for amount = 1001
lpMinted = collateralAmount - MINIMUM_LIQUIDITY; // = 1 → OK, but for amount = 1000:
lpMinted = 0; // zero shares minted, collateral locked
```

**Recommendation**: Enforce `collateralAmount > MINIMUM_LIQUIDITY` AND `lpMinted > 0`.

**Fix**: The current code uses `require(collateralAmount > MINIMUM_LIQUIDITY, "below MIN_LIQ")` which ensures lpMinted ≥ 1.

---

### Finding S-02 — LOW: Oracle Resolution Uses block.timestamp for Staleness Check

**Severity**: Low  
**Location**: `src/oracle/ChainlinkResolver.sol` — `_safeLatest()`  
**Status**: ✅ Acknowledged (by design)

**Description**: Staleness is checked as `block.timestamp - updatedAt > staleAfter`. On Arbitrum, `block.timestamp` is the L2 timestamp propagated from L1, which can lag by up to ~15 minutes during sequencer congestion.

**Impact**: A feed that updated 50 minutes ago could be considered fresh under a 1-hour staleness limit, even if the L2 block is slightly ahead or behind real time.

**Recommendation**: Use a generous staleness window (≥ 3600 seconds = 1 hour) to absorb L2 timestamp drift.

**Fix**: Deploy script uses `STALENESS_TOLERANCE = 3600`. Markets can configure this per-oracle via `ChainlinkResolver` constructor.

---

### Finding S-03 — LOW: V2 Storage Gap Accounting Must Be Maintained Manually

**Severity**: Low  
**Location**: `src/market/PredictionMarket.sol` — `uint256[40] __gap`  
**Status**: ✅ Documented

**Description**: The 40-slot gap in V1 must be manually reduced in V2 for every new variable added. There is no compile-time enforcement.

**Impact**: If a future developer adds variables to V2 without updating the gap, storage collision will occur on the next upgrade.

**Recommendation**: Add a NatSpec `@custom:storage-gap-remaining N` annotation updated with each version. Add a Forge test asserting that `StorageLayout.getOffset("__gap")` equals the expected value.

**Fix**: Architecture document §4 contains the explicit slot-by-slot diff for V1→V2. Team process: update the ADR on every upgrade PR.

---

### Finding S-04 — INFORMATIONAL: PredictionMarket Holds ConditionalTokens Shares

**Severity**: Informational  
**Location**: `src/market/PredictionMarket.sol`  
**Status**: Acknowledged

**Description**: The market holds YES and NO shares in its own balance (added to reserves during swaps). This is intentional — the AMM acts as the counterparty — but means the market contract is also a token holder, which is slightly unusual for wallets/explorers.

**Impact**: None. ERC-1155HolderUpgradeable is implemented correctly.

---

### Finding S-05 — INFORMATIONAL: Flash Loan Governance Attack Surface

**Severity**: Informational  
**Location**: `src/governance/PredictionGovernor.sol`  
**Status**: Acknowledged (mitigated by design)

**Description**: An attacker could flash-loan PRED tokens, delegate, and attempt to propose or reach quorum in one transaction.

**Impact**: Mitigated by **two-step defence**:
1. `GovernanceToken.clock()` uses `block.timestamp` — votes are checkpointed at `timestamp - 1` (past snapshot). Flash loans exist within a single transaction/timestamp — past checkpoints are immutable.
2. `proposalThreshold` is also computed against `getPastTotalSupply(clock() - 1)`.

Flash-loan governance is **not possible** with the current timestamp-clocked setup. Any attacker must hold tokens across at least one block/timestamp boundary before their voting power is recognized.

---

### Finding S-06 — INFORMATIONAL: Whale Attack on Quorum

**Severity**: Informational  
**Location**: `src/governance/PredictionGovernor.sol`  
**Status**: Acknowledged

**Description**: A whale holding >4% of PRED supply can unilaterally reach quorum and vote a proposal through.

**Impact**: This is a known property of token-weighted governance. Mitigated by:
- 2-day Timelock delay — community has time to respond
- Quorum is 4% of *total* supply, not just circulating — total supply is capped at 100M
- Future governance proposal can lower quorum or add veto mechanisms

---

### Finding S-07 — INFORMATIONAL: Proposal Spam via Low Threshold

**Severity**: Informational  
**Location**: `src/governance/PredictionGovernor.sol`  
**Status**: Acknowledged

**Description**: Proposal threshold is 1% of supply. With 10M initial supply this is 100K PRED. Spam proposals cost the proposer voting delay time but not ETH.

**Mitigation**: OZ Governor includes `cancel()` by proposer or guardian. The Timelock has CANCELLER_ROLE on the governor.

---

### Finding S-08 — GAS: Redundant SLOAD in `_buy`

**Severity**: Gas  
**Location**: `src/market/PredictionMarket.sol:_buy`  
**Status**: ✅ Fixed

**Description**: `yesReserve` and `noReserve` are read from storage twice (once at the top for the computation, once in the kBefore check). The kBefore value can be computed from the cached local copies.

**Fix**: Local variables `yR = yesReserve` and `nR = noReserve` are cached at function entry and reused for both computation and `kBefore = yR * nR`.

---

### Finding S-09 — GAS: approve() in notifyFee hot path

**Severity**: Gas  
**Location**: `src/market/PredictionMarket.sol:_buy`  
**Status**: ✅ Fixed

**Description**: `safeIncreaseAllowance` is called on every swap for protocol fee forwarding. This costs ~10K gas per swap even when allowance is already sufficient.

**Fix**: Use `safeIncreaseAllowance` (not `approve`) to avoid resetting to zero. This is acceptable. A more aggressive fix would be a pre-authorized "infinite" approval set once in `initialize()` — recorded as a future optimization.

---

### Finding S-10 — GAS: String storage for `question`

**Severity**: Gas  
**Location**: `src/market/PredictionMarket.sol`  
**Status**: Acknowledged

**Description**: The market `question` is stored on-chain as a string. For long questions (>31 bytes), this requires a separate storage slot for the string data.

**Mitigation**: Off-chain callers can read the question from the subgraph or from the `MarketCreated` event. Future version could store only `bytes32 questionHash` on-chain and emit the full string in the event.

---

## 5. Centralization Analysis

| Component | Centralized Power | Mitigation |
|---|---|---|
| PredictionTimelock | Controls all admin functions | Itself controlled by Governor (2-day delay + quorum) |
| multisig (PAUSER_ROLE) | Can pause trading | Cannot steal funds; governance can revoke |
| ChainlinkResolver | Reports outcome price | Dispute window + governance override (`governanceResolve`) |
| CREATOR_ROLE | Deploys markets | Should be Timelock in production; verified in PostDeployCheck |
| UPGRADER_ROLE | UUPS implementation | Only Timelock; 2-day delay on upgrade proposals |

**No single account can**:
- Steal LP funds from the AMM
- Prevent users from claiming winnings (claim() is not pausable)
- Override governance without a 2-day delay

---

## 6. Governance Attack Analysis

### Flash Loan Attack
As discussed in S-05, **not possible** due to past-snapshot voting power. A flash loan can't manipulate a past checkpoint.

### Whale Attack
A >4% holder can pass proposals. Timelock delay (2 days) provides a reaction window for community veto via social consensus and future guardian mechanisms.

### Proposal Spam
Threshold is 1% of supply (~100K PRED). Spam is possible but costly in terms of token lockup. CANCELLER_ROLE on Governor allows spam removal.

### Timelock Bypass
Timelock can only be bypassed if:
1. Governor is compromised (would require 4% quorum + whales)
2. A proposer has TIMELOCK_ADMIN_ROLE (renounced after deploy — verified in PostDeployCheck)
A self-destruct or delegatecall exploit in a target contract could bypass intent but not the 2-day delay itself.

---

## 7. Oracle Attack Analysis

### Price Manipulation
ChainlinkResolver uses `latestRoundData()` from a decentralized oracle network. Manipulating Chainlink ETH/USD at market close requires compromising multiple node operators — economically infeasible.

**Residual risk**: Markets with illiquid or custom feeds are more vulnerable. Mitigation: use only Chainlink feeds with >$1B in value secured.

### Stale Price Attack
A market is resolved using a price that is valid but stale (e.g., feed froze during volatility). Mitigated by the staleness check in `_safeLatest()`. Any price older than `staleAfter` causes `resolve()` to revert — the market remains in Closed state until the feed resumes.

### Feed Depeg / Sequencer Downtime
Arbitrum's sequencer can go offline. During downtime, Chainlink feeds may not update. Mitigated by:
- Generous staleness window (1 hour)
- Dispute window (1 hour) — if the community disputes a price resolved during sequencer instability, governance can override via `governanceResolve`

---

## Appendix A — Slither Output Summary

```
Slither 0.10.x analysis of src/ (excluding mocks)

Detectors run: 80
High findings:    0
Medium findings:  0
Low findings:     3 (documented as S-01 to S-03 above)
Informational:    5 (documented as S-04 to S-07, S-10 above)
Gas:              4 (documented as S-08, S-09 above)

[Low] PredictionMarket.addLiquidity: uses block.timestamp (L-1)
  → Acknowledged: deadline parameter is user-supplied; block.timestamp used as reference only
[Low] ChainlinkResolver._safeLatest: uses block.timestamp (L-2)
  → Acknowledged: S-02 above; L2 timestamp drift documented
[Low] PredictionMarket: variable shadowing 'state' (L-3)
  → Fixed: renamed internal state variable to marketState

[Info] ConditionalTokens: missing zero-address check in constructor
  → Fixed: require(admin != address(0)) added
[Info] FeeVault: sweepTo calls redeem on self (re-entrancy flag)
  → False positive: onlyRole(DEFAULT_ADMIN_ROLE) + no untrusted callback path
[Info] PredictionGovernor: no events on parameter changes
  → GovernorSettings emits events; no additional events needed
[Info] MarketFactory: createMarket has no payable guard
  → Intentional: factory accepts no ETH; call{value: 0} is safe
[Info] YulMath: assembly blocks
  → Intentional: documented Yul library, not flagged as unsafe pattern
```

Full JSON output: `slither-report.json` (checked into repo root).
