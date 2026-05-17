import { useReadContract, useAccount } from "wagmi";
import { formatUnits } from "viem";
import { ADDRESSES, GOV_TOKEN_ABI } from "../contracts";

export function PortfolioPanel() {
  const { address } = useAccount();

  const { data: balance } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: votes } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "getVotes",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (!address) return <div className="panel">Please connect your wallet to see your portfolio.</div>;

  return (
    <div className="panel">
      <h3>Your Portfolio</h3>
      <div className="stat">
        <label>PRED Balance:</label>
        <span>{balance ? formatUnits(balance, 18) : "0.00"}</span>
      </div>
      <div className="stat">
        <label>Voting Power:</label>
        <span>{votes ? formatUnits(votes, 18) : "0.00"}</span>
      </div>
    </div>
  );
}
