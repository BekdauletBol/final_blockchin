import { useReadContract, useAccount } from "wagmi";
import { formatUnits } from "viem";
import { ADDRESSES, GOV_TOKEN_ABI, VAULT_ABI, MARKET_ABI } from "../contracts";

export function PortfolioPanel() {
  const { address } = useAccount();

  const { data: balance } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (balance) console.log("PRED Balance (raw):", balance.toString());

  const { data: votes } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "getVotes",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: vaultShares } = useReadContract({
    address: ADDRESSES.feeVault,
    abi: VAULT_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: vaultAssets } = useReadContract({
    address: ADDRESSES.feeVault,
    abi: VAULT_ABI,
    functionName: "convertToAssets",
    args: vaultShares ? [vaultShares as bigint] : undefined,
    query: { enabled: !!(vaultShares && (vaultShares as bigint) > 0n) },
  });

  const { data: winnings } = useReadContract({
    address: ADDRESSES.market1,
    abi: MARKET_ABI,
    functionName: "winningsFor",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (!address) return <div className="panel">Please connect your wallet to see your portfolio.</div>;

  return (
    <div className="portfolio-container">
      <div className="panel">
        <h3>💰 Token Balances</h3>
        <div className="stat">
          <label>PRED Balance:</label>
          <span>{balance ? formatUnits(balance, 18) : "0.00"}</span>
        </div>
        <div className="stat">
          <label>Voting Power:</label>
          <span>{votes ? formatUnits(votes, 18) : "0.00"}</span>
        </div>
      </div>

      <div className="panel">
        <h3>🏦 Fee Vault Position</h3>
        <div className="stat">
          <label>Vault Shares:</label>
          <span>{vaultShares ? formatUnits(vaultShares as bigint, 6) : "0.00"}</span>
        </div>
        <div className="stat">
          <label>Estimated Value:</label>
          <span>{vaultAssets ? formatUnits(vaultAssets as bigint, 6) : "0.00"} USDC</span>
        </div>
      </div>

      {winnings && (winnings as bigint) > 0n && (
        <div className="panel success">
          <h3>🏆 Claimable Winnings</h3>
          <div className="stat">
            <label>Amount:</label>
            <span>{formatUnits(winnings as bigint, 6)} USDC</span>
          </div>
        </div>
      )}
    </div>
  );
}
