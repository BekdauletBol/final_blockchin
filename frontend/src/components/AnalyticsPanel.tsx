import React from "react";
import { useQuery } from "@tanstack/react-query";
import { request, gql } from "graphql-request";
import { formatUnits } from "viem";
import { MARKET_STATE } from "../contracts";

const SUBGRAPH_URL = "https://api.studio.thegraph.com/query/1753430/slug/v0.0.1";

const ANALYTICS_QUERY = gql`
  query Analytics($since: BigInt!) {
    markets(first: 10, orderBy: totalCollateralIn, orderDirection: desc) {
      id
      question
      state
      totalCollateralIn
      totalFeesProtocol
    }
    vaultSnapshots(orderBy: blockNumber, orderDirection: desc, first: 1) {
      totalAssets
      totalShares
      timestamp
    }
  }
`;

export function AnalyticsPanel() {
  const since = (Math.floor(Date.now() / 1000) - 7 * 86400).toString();

  const { data, isLoading, error } = useQuery({
    queryKey: ["analytics", since],
    queryFn: async () => request(SUBGRAPH_URL, ANALYTICS_QUERY, { since }),
  });

  if (isLoading) return <div className="panel">Loading from subgraph...</div>;
  if (error) return <div className="panel error">Subgraph error: {(error as Error).message}</div>;

  const markets = (data as any)?.markets || [];
  const snap = (data as any)?.vaultSnapshots?.[0];

  return (
    <div className="analytics-container">
      <div className="panel">
        <h3>🏦 Fee Vault Statistics</h3>
        {snap ? (
          <>
            <div className="stat">
              <label>Total Assets:</label>
              <span>{formatUnits(BigInt(snap.totalAssets), 6)} USDC</span>
            </div>
            <div className="stat">
              <label>Total Shares:</label>
              <span>{formatUnits(BigInt(snap.totalShares), 6)}</span>
            </div>
          </>
        ) : (
          <p className="info">No vault data indexed yet.</p>
        )}
      </div>

      <div className="panel">
        <h3>📈 All Markets</h3>
        {markets.length === 0 ? (
          <p className="info">No markets found.</p>
        ) : (
          markets.map((m: any) => (
            <div key={m.id} className="market-item-mini">
              <strong>{m.question}</strong>
              <div className="stat-mini">
                <span>Volume: {formatUnits(BigInt(m.totalCollateralIn), 6)} USDC</span>
                <span className={`badge state-${m.state}`}>{MARKET_STATE[m.state]}</span>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

