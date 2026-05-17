import { useQuery } from "@tanstack/react-query";
import { request, gql } from "graphql-request";

const SUBGRAPH_URL = "https://api.studio.thegraph.com/query/1753430/slug/v0.0.1";

const MARKETS_QUERY = gql`
  query GetActiveMarkets {
    markets(where: { state: 0 }) {
      id
      question
      yesReserve
      noReserve
      totalCollateralIn
    }
  }
`;

export function AnalyticsPanel() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["activeMarkets"],
    queryFn: async () => request(SUBGRAPH_URL, MARKETS_QUERY),
  });

  if (isLoading) return <div className="panel">Loading subgraph data...</div>;
  if (error) return <div className="panel">Error fetching from subgraph: {(error as Error).message}</div>;

  const markets = (data as any)?.markets || [];

  return (
    <div className="panel">
      <h3>Global Market Analytics (via The Graph)</h3>
      {markets.length === 0 ? (
        <p>No active markets found in subgraph.</p>
      ) : (
        <ul className="analytics-list">
          {markets.map((m: any) => (
            <li key={m.id}>
              <strong>{m.question}</strong>
              <div>Liquidity (YES/NO): {m.yesReserve} / {m.noReserve}</div>
              <div>Volume: {m.totalCollateralIn}</div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
