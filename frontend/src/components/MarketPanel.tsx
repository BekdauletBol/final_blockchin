import { useState } from "react";
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { ADDRESSES, MARKET_ABI, MARKET_STATE, ERC20_ABI } from "../contracts";

export function MarketPanel() {
  const [amount, setAmount] = useState("10");
  
  const { data: marketInfo } = useReadContract({
    address: ADDRESSES.market1,
    abi: MARKET_ABI,
    functionName: "info",
  });

  const { data: hash, writeContract, isPending } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const handlePredict = (isYes: boolean) => {
    const val = parseUnits(amount, 6); // Assuming USDC 6 decimals
    writeContract({
      address: ADDRESSES.market1,
      abi: MARKET_ABI,
      functionName: isYes ? "buyYes" : "buyNo",
      args: [val, BigInt(0), BigInt(Math.floor(Date.now() / 1000) + 3600)],
    });
  };

  const handleApprove = () => {
    const val = parseUnits(amount, 6);
    // Finding collateral token from market info
    const collateral = marketInfo?.[3] as `0x${string}`;
    if (!collateral) return;

    writeContract({
      address: collateral,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [ADDRESSES.market1, val],
    });
  };

  if (!marketInfo) return <div className="panel">Loading market data...</div>;

  return (
    <div className="panel">
      <h3>Active Market</h3>
      <p className="question">{marketInfo[0]}</p>
      <div className="market-stats">
        <div>State: {MARKET_STATE[marketInfo[5]]}</div>
        <div>Total Collateral: {formatUnits(marketInfo[7], 6)} USDC</div>
      </div>

      <div className="trade-actions">
        <input 
          type="number" 
          value={amount} 
          onChange={(e) => setAmount(e.target.value)} 
          placeholder="Amount in USDC"
        />
        <div className="btn-group">
          <button onClick={handleApprove} disabled={isPending || isConfirming}>Approve</button>
          <button onClick={() => handlePredict(true)} disabled={isPending || isConfirming} className="btn-yes">Predict YES</button>
          <button onClick={() => handlePredict(false)} disabled={isPending || isConfirming} className="btn-no">Predict NO</button>
        </div>
      </div>

      {hash && <div className="tx-status">Tx Hash: {hash}</div>}
      {isConfirming && <div>Waiting for confirmation...</div>}
      {isSuccess && <div className="success">Transaction Successful!</div>}
    </div>
  );
}
