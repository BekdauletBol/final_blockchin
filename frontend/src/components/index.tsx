import React, { useState } from "react";
import {
  useAccount, useConnect, useDisconnect,
  useReadContract, useReadContracts,
  useWriteContract, useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, parseUnits, keccak256, toBytes } from "viem";
import { request, gql } from "graphql-request";

import {
  ADDRESSES, MARKET_ABI, GOV_TOKEN_ABI, GOVERNOR_ABI,
  ERC20_ABI, CONDITIONAL_TOKENS_ABI, VAULT_ABI,
  PROPOSAL_STATE, MARKET_STATE, MARKET_OUTCOME,
} from "../contracts";

// ─── Subgraph endpoint ────────────────────────────────────────────────────────
const SUBGRAPH_URL = import.meta.env.VITE_SUBGRAPH_URL ??
  "https://api.studio.thegraph.com/query/YOUR_ID/prediction-market-arb-sepolia/version/latest";

// ─── Shared card styles ───────────────────────────────────────────────────────
const S: Record<string, React.CSSProperties> = {
  card:   { background: "#1a1a27", border: "1px solid #2a2a3a", borderRadius: 14, padding: 24, marginBottom: 20 },
  h2:     { marginTop: 0, fontSize: 18, fontWeight: 700 },
  label:  { display: "block", fontSize: 13, color: "#8888a8", marginBottom: 4 },
  input:  { width: "100%", background: "#111118", border: "1px solid #333350", borderRadius: 8,
            color: "#e8e8f0", padding: "10px 14px", fontSize: 15, boxSizing: "border-box" },
  btn:    { background: "#5a4fff", border: "none", borderRadius: 10, color: "#fff",
            cursor: "pointer", padding: "12px 24px", fontWeight: 700, fontSize: 15, width: "100%", marginTop: 12 },
  yesBtn: { background: "#22c55e" },
  noBtn:  { background: "#ef4444" },
  stat:   { display: "flex", justifyContent: "space-between", padding: "6px 0",
            borderBottom: "1px solid #22223a" },
  badge:  { borderRadius: 6, padding: "2px 10px", fontSize: 12, fontWeight: 700 },
  err:    { color: "#ef4444", fontSize: 13, marginTop: 8 },
  info:   { color: "#8888a8", fontSize: 13, marginTop: 8 },
};

// ═══════════════════════════════════════════════════════════════════════════════
//  WalletButton
// ═══════════════════════════════════════════════════════════════════════════════
export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors }  = useConnect();
  const { disconnect }           = useDisconnect();

  if (isConnected) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontSize: 13, color: "#8888a8" }}>
          {address?.slice(0,6)}…{address?.slice(-4)}
        </span>
        <button onClick={() => disconnect()}
          style={{ ...S.btn, width: "auto", padding: "8px 18px", background: "#2a2a3a" }}>
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", gap: 8 }}>
      {connectors.map(c => (
        <button key={c.id} onClick={() => connect({ connector: c })}
          style={{ ...S.btn, width: "auto", padding: "8px 18px" }}>
          {c.name}
        </button>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MarketPanel — market info + swap + add liquidity
// ═══════════════════════════════════════════════════════════════════════════════
export function MarketPanel() {
  const { address } = useAccount();
  const [amount, setAmount]  = useState("");
  const [side, setSide]      = useState<"yes"|"no">("yes");
  const [lpAmt, setLpAmt]    = useState("");
  const [txErr, setTxErr]    = useState("");

  // ── Read market info ─────────────────────────────────────────────────────
  const { data: infoData } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "info",
  });
  const { data: reserves } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "reserves",
  });
  const { data: priceYes } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "priceYes",
  });
  const { data: winnings } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "winningsFor",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: yesId } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "yesTokenId",
  });
  const { data: noId } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "noTokenId",
  });
  const { data: yesBal } = useReadContract({
    address: ADDRESSES.conditionalTokens, abi: CONDITIONAL_TOKENS_ABI,
    functionName: "balanceOf",
    args: address && yesId ? [address, yesId] : undefined,
    query: { enabled: !!(address && yesId) },
  });
  const { data: noBal } = useReadContract({
    address: ADDRESSES.conditionalTokens, abi: CONDITIONAL_TOKENS_ABI,
    functionName: "balanceOf",
    args: address && noId ? [address, noId] : undefined,
    query: { enabled: !!(address && noId) },
  });

  // ── Quote ────────────────────────────────────────────────────────────────
  const parsedAmt = (() => { try { return parseUnits(amount || "0", 6); } catch { return 0n; } })();
  const { data: quote } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI,
    functionName: side === "yes" ? "quoteBuyYes" : "quoteBuyNo",
    args: [parsedAmt],
    query: { enabled: parsedAmt > 0n },
  });

  // ── Writes ───────────────────────────────────────────────────────────────
  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const deadline = () => BigInt(Math.floor(Date.now() / 1000) + 3600);

  function handleSwap() {
    if (!amount) return;
    setTxErr("");
    const fn = side === "yes" ? "buyYes" : "buyNo";
    try {
      writeContract({
        address: ADDRESSES.market1, abi: MARKET_ABI, functionName: fn,
        args: [parseUnits(amount, 6), 0n, deadline()],
      });
    } catch (e: any) { setTxErr(e?.shortMessage ?? String(e)); }
  }

  function handleAddLiquidity() {
    if (!lpAmt) return;
    setTxErr("");
    try {
      writeContract({
        address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "addLiquidity",
        args: [parseUnits(lpAmt, 6), 0n, deadline()],
      });
    } catch (e: any) { setTxErr(e?.shortMessage ?? String(e)); }
  }

  function handleClaim() {
    setTxErr("");
    try {
      writeContract({ address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "claim", args: [] });
    } catch (e: any) { setTxErr(e?.shortMessage ?? String(e)); }
  }

  const marketState = Number((infoData as any)?.state ?? 0);
  const outcome     = Number((infoData as any)?.outcome ?? 0);

  return (
    <div>
      {/* Market info */}
      <div style={S.card}>
        <h2 style={S.h2}>📊 Market</h2>
        <p style={{ color: "#c8c8e8", marginTop: 4 }}>
          {(infoData as any)?.question ?? "Loading…"}
        </p>
        <div style={S.stat}><span>Status</span>
          <span style={{ ...S.badge, background: marketState === 0 ? "#1a3a1a" : "#2a1a0a",
            color: marketState === 0 ? "#22c55e" : "#ffb347" }}>
            {MARKET_STATE[marketState] ?? "Unknown"}
          </span>
        </div>
        {outcome > 0 && (
          <div style={S.stat}><span>Outcome</span>
            <span style={{ ...S.badge, background: "#1a1a3a", color: "#a0a0ff" }}>
              {MARKET_OUTCOME[outcome]}
            </span>
          </div>
        )}
        <div style={S.stat}><span>YES Price</span>
          <span>{priceYes ? `${(Number(priceYes) / 1e18 * 100).toFixed(1)}¢` : "—"}</span>
        </div>
        <div style={S.stat}><span>YES Reserve</span>
          <span>{reserves ? formatUnits((reserves as any)[0], 6) + " USDC" : "—"}</span>
        </div>
        <div style={S.stat}><span>NO Reserve</span>
          <span>{reserves ? formatUnits((reserves as any)[1], 6) + " USDC" : "—"}</span>
        </div>
        {address && (
          <>
            <div style={S.stat}><span>Your YES shares</span>
              <span>{yesBal ? formatUnits(yesBal as bigint, 6) : "0"}</span>
            </div>
            <div style={S.stat}><span>Your NO shares</span>
              <span>{noBal ? formatUnits(noBal as bigint, 6) : "0"}</span>
            </div>
          </>
        )}
      </div>

      {/* Swap */}
      {marketState === 0 && (
        <div style={S.card}>
          <h2 style={S.h2}>⚡ Trade</h2>
          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <button onClick={() => setSide("yes")}
              style={{ ...S.btn, ...S.yesBtn, opacity: side === "yes" ? 1 : 0.4 }}>YES</button>
            <button onClick={() => setSide("no")}
              style={{ ...S.btn, ...S.noBtn,  opacity: side === "no"  ? 1 : 0.4 }}>NO</button>
          </div>
          <label style={S.label}>Collateral (USDC)</label>
          <input style={S.input} type="number" placeholder="0.00"
            value={amount} onChange={e => setAmount(e.target.value)} />
          {quote && parsedAmt > 0n && (
            <p style={S.info}>≈ {formatUnits(quote as bigint, 6)} {side.toUpperCase()} shares</p>
          )}
          <button style={S.btn} onClick={handleSwap}
            disabled={!address || isPending || isConfirming}>
            {isPending || isConfirming ? "Confirming…" : `Buy ${side.toUpperCase()}`}
          </button>
          {txErr && <p style={S.err}>{txErr}</p>}
        </div>
      )}

      {/* Add Liquidity */}
      {marketState === 0 && (
        <div style={S.card}>
          <h2 style={S.h2}>💧 Add Liquidity</h2>
          <label style={S.label}>USDC amount</label>
          <input style={S.input} type="number" placeholder="0.00"
            value={lpAmt} onChange={e => setLpAmt(e.target.value)} />
          <button style={S.btn} onClick={handleAddLiquidity}
            disabled={!address || isPending}>
            Add Liquidity
          </button>
        </div>
      )}

      {/* Claim */}
      {marketState === 4 && address && (winnings as bigint) > 0n && (
        <div style={S.card}>
          <h2 style={S.h2}>🏆 Claim Winnings</h2>
          <p>You can claim: {formatUnits(winnings as bigint, 6)} USDC</p>
          <button style={{ ...S.btn, background: "#f59e0b" }} onClick={handleClaim}
            disabled={isPending}>Claim</button>
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GovernancePanel — proposal list + vote
// ═══════════════════════════════════════════════════════════════════════════════

const PROPOSALS_QUERY = gql`
  query {
    markets(first: 5, orderBy: createdAtTimestamp, orderDirection: desc) {
      id question state createdAtTimestamp totalCollateralIn totalFeesProtocol
    }
  }
`;

interface SubgraphMarket {
  id: string; question: string; state: number;
  createdAtTimestamp: string; totalCollateralIn: string; totalFeesProtocol: string;
}

// Hardcoded demo proposals — in production pull from on-chain events
const DEMO_PROPOSALS = [
  { id: "1", description: "Add ETH>$4000 market for Q3 2026", state: 1 },
  { id: "2", description: "Reduce dispute window to 30 minutes",  state: 4 },
  { id: "3", description: "Mint 500k PRED tokens to liquidity mining vault", state: 7 },
];

export function GovernancePanel() {
  const { address }                = useAccount();
  const [votingId, setVotingId]    = useState<string | null>(null);
  const [support, setSupport]      = useState<0|1|2>(1);
  const { writeContract, isPending } = useWriteContract();

  const { data: govBalance } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: votingPower } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "getVotes",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: delegate } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "delegates",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  function handleVote() {
    if (!votingId) return;
    writeContract({
      address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "castVote",
      args: [BigInt(votingId), support],
    });
  }

  function handleDelegate() {
    if (!address) return;
    writeContract({
      address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "delegate",
      args: [address],
    });
  }

  const stateColor: Record<number, string> = {
    0: "#888", 1: "#22c55e", 3: "#ef4444", 4: "#3b82f6", 5: "#f59e0b", 7: "#a855f7"
  };

  return (
    <div>
      {/* Voting power */}
      <div style={S.card}>
        <h2 style={S.h2}>🗳️ Your Governance Power</h2>
        <div style={S.stat}><span>PRED Balance</span>
          <span>{govBalance ? formatUnits(govBalance as bigint, 18) : "0"}</span>
        </div>
        <div style={S.stat}><span>Voting Power</span>
          <span>{votingPower ? formatUnits(votingPower as bigint, 18) : "0"}</span>
        </div>
        <div style={S.stat}><span>Delegating to</span>
          <span style={{ fontSize: 12 }}>
            {delegate ? `${(delegate as string).slice(0,8)}…` : "—"}
          </span>
        </div>
        {(votingPower as bigint) === 0n && (
          <button style={{ ...S.btn, background: "#334" }} onClick={handleDelegate}
            disabled={!address || isPending}>
            Delegate to myself
          </button>
        )}
      </div>

      {/* Proposals */}
      <div style={S.card}>
        <h2 style={S.h2}>📋 Proposals</h2>
        {DEMO_PROPOSALS.map(p => (
          <div key={p.id} style={{ ...S.card, background: "#111118", marginBottom: 12 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <span style={{ fontSize: 14 }}>{p.description}</span>
              <span style={{ ...S.badge, background: stateColor[p.state] + "30",
                color: stateColor[p.state] ?? "#888" }}>
                {PROPOSAL_STATE[p.state]}
              </span>
            </div>
            {p.state === 1 && (
              <div style={{ marginTop: 12 }}>
                <div style={{ display: "flex", gap: 6, marginBottom: 8 }}>
                  {([1, 0, 2] as const).map(s => (
                    <button key={s} onClick={() => { setVotingId(p.id); setSupport(s); }}
                      style={{ ...S.btn, width: "auto", padding: "6px 14px", fontSize: 13,
                        background: support === s && votingId === p.id
                          ? s === 1 ? "#22c55e" : s === 0 ? "#ef4444" : "#888"
                          : "#2a2a3a" }}>
                      {s === 1 ? "For" : s === 0 ? "Against" : "Abstain"}
                    </button>
                  ))}
                </div>
                {votingId === p.id && (
                  <button style={S.btn} onClick={handleVote} disabled={!address || isPending}>
                    Cast Vote
                  </button>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PortfolioPanel — user's shares + vault position
// ═══════════════════════════════════════════════════════════════════════════════
export function PortfolioPanel() {
  const { address } = useAccount();

  const { data: vaultShares } = useReadContract({
    address: ADDRESSES.feeVault, abi: VAULT_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: vaultAssets } = useReadContract({
    address: ADDRESSES.feeVault, abi: VAULT_ABI, functionName: "convertToAssets",
    args: vaultShares ? [vaultShares as bigint] : undefined,
    query: { enabled: !!(vaultShares && (vaultShares as bigint) > 0n) },
  });
  const { data: yesId } = useReadContract({ address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "yesTokenId" });
  const { data: noId  } = useReadContract({ address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "noTokenId"  });
  const { data: yesBal } = useReadContract({
    address: ADDRESSES.conditionalTokens, abi: CONDITIONAL_TOKENS_ABI, functionName: "balanceOf",
    args: address && yesId ? [address, yesId as bigint] : undefined,
    query: { enabled: !!(address && yesId) },
  });
  const { data: noBal } = useReadContract({
    address: ADDRESSES.conditionalTokens, abi: CONDITIONAL_TOKENS_ABI, functionName: "balanceOf",
    args: address && noId ? [address, noId as bigint] : undefined,
    query: { enabled: !!(address && noId) },
  });
  const { data: winnings } = useReadContract({
    address: ADDRESSES.market1, abi: MARKET_ABI, functionName: "winningsFor",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (!address) return <div style={S.card}><p>Connect wallet to see your portfolio.</p></div>;

  return (
    <div>
      <div style={S.card}>
        <h2 style={S.h2}>📦 My Positions — Market #1</h2>
        <div style={S.stat}><span>YES Shares</span>
          <span>{yesBal ? formatUnits(yesBal as bigint, 6) : "0"}</span>
        </div>
        <div style={S.stat}><span>NO Shares</span>
          <span>{noBal ? formatUnits(noBal as bigint, 6) : "0"}</span>
        </div>
        <div style={S.stat}><span>Claimable Winnings</span>
          <span style={{ color: "#22c55e" }}>
            {winnings ? formatUnits(winnings as bigint, 6) + " USDC" : "0"}
          </span>
        </div>
      </div>
      <div style={S.card}>
        <h2 style={S.h2}>🏦 Fee Vault Position</h2>
        <div style={S.stat}><span>Vault Shares</span>
          <span>{vaultShares ? formatUnits(vaultShares as bigint, 6) : "0"}</span>
        </div>
        <div style={S.stat}><span>Estimated Value</span>
          <span>{vaultAssets ? formatUnits(vaultAssets as bigint, 6) + " USDC" : "0"}</span>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AnalyticsPanel — reads from The Graph subgraph
// ═══════════════════════════════════════════════════════════════════════════════

const ANALYTICS_QUERY = gql`
  query Analytics($since: BigInt!) {
    markets(first: 10, orderBy: totalCollateralIn, orderDirection: desc) {
      id question state totalCollateralIn totalFeesProtocol totalFeesLP
    }
    feeEvents(where: { timestamp_gte: $since }, orderBy: timestamp, orderDirection: desc, first: 10) {
      source amount timestamp txHash
    }
    vaultSnapshots(orderBy: blockNumber, orderDirection: desc, first: 1) {
      totalAssets totalShares timestamp
    }
  }
`;

export function AnalyticsPanel() {
  const [data, setData]   = React.useState<any>(null);
  const [loading, setLoading] = React.useState(false);
  const [err, setErr]     = React.useState("");

  React.useEffect(() => {
    setLoading(true);
    const since = BigInt(Math.floor(Date.now() / 1000) - 7 * 86400).toString();
    request(SUBGRAPH_URL, ANALYTICS_QUERY, { since })
      .then(d => { setData(d); setLoading(false); })
      .catch(e => { setErr(String(e)); setLoading(false); });
  }, []);

  if (loading) return <div style={S.card}><p>Loading from subgraph…</p></div>;
  if (err)     return <div style={S.card}><p style={S.err}>Subgraph error: {err}</p></div>;
  if (!data)   return null;

  const snap = data.vaultSnapshots?.[0];

  return (
    <div>
      {/* Vault snapshot */}
      <div style={S.card}>
        <h2 style={S.h2}>🏦 Fee Vault (live from subgraph)</h2>
        {snap ? (
          <>
            <div style={S.stat}><span>Total Assets</span>
              <span>{formatUnits(BigInt(snap.totalAssets), 6)} USDC</span>
            </div>
            <div style={S.stat}><span>Total Shares</span>
              <span>{formatUnits(BigInt(snap.totalShares), 6)}</span>
            </div>
          </>
        ) : <p style={S.info}>No vault data yet.</p>}
      </div>

      {/* Markets table */}
      <div style={S.card}>
        <h2 style={S.h2}>📈 All Markets (from subgraph)</h2>
        {data.markets?.map((m: SubgraphMarket) => (
          <div key={m.id} style={{ ...S.card, background: "#111118", marginBottom: 10 }}>
            <p style={{ margin: "0 0 8px", fontWeight: 600 }}>{m.question}</p>
            <div style={S.stat}><span>Volume</span>
              <span>{formatUnits(BigInt(m.totalCollateralIn), 6)} USDC</span>
            </div>
            <div style={S.stat}><span>Protocol Fees</span>
              <span>{formatUnits(BigInt(m.totalFeesProtocol), 6)} USDC</span>
            </div>
            <div style={S.stat}><span>State</span>
              <span>{MARKET_STATE[m.state] ?? "Unknown"}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Recent fee events */}
      <div style={S.card}>
        <h2 style={S.h2}>⚡ Recent Fee Events (7d)</h2>
        {data.feeEvents?.length === 0 && <p style={S.info}>No fees collected yet.</p>}
        {data.feeEvents?.map((f: any, i: number) => (
          <div key={i} style={S.stat}>
            <span style={{ fontSize: 12, color: "#6668" }}>{f.source.slice(0,10)}…</span>
            <span style={{ color: "#22c55e" }}>+{formatUnits(BigInt(f.amount), 6)} USDC</span>
          </div>
        ))}
      </div>
    </div>
  );
}
