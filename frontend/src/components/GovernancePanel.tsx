import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { formatUnits } from "viem";
import { ADDRESSES, GOV_TOKEN_ABI, GOVERNOR_ABI, PROPOSAL_STATE } from "../contracts";

const DEMO_PROPOSALS = [
  { id: "1", description: "Add ETH>$4000 market for Q3 2026", state: 1 },
  { id: "2", description: "Reduce dispute window to 30 minutes",  state: 4 },
];

export function GovernancePanel() {
  const { address } = useAccount();
  const [votingId, setVotingId] = useState<string | null>(null);
  const [support, setSupport] = useState<number>(1); // 1 = For
  const { writeContract, isPending } = useWriteContract();

  const { data: delegate } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "delegates",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const handleVote = () => {
    if (!votingId) return;
    writeContract({
      address: ADDRESSES.governor,
      abi: GOVERNOR_ABI,
      functionName: "castVote",
      args: [BigInt(votingId), support],
    });
  };

  const handleDelegate = () => {
    if (!address) return;
    writeContract({
      address: ADDRESSES.govToken,
      abi: GOV_TOKEN_ABI,
      functionName: "delegate",
      args: [address],
    });
  };

  return (
    <div className="governance-container">
      <div className="panel">
        <h3>🗳️ Governance</h3>
        <div className="stat">
          <label>Delegating to:</label>
          <span>{delegate ? `${(delegate as string).slice(0, 8)}...` : "None"}</span>
        </div>
        {!delegate || delegate === "0x0000000000000000000000000000000000000000" ? (
          <button onClick={handleDelegate} disabled={isPending} className="btn-primary" style={{marginTop: '10px'}}>
            Delegate to Self
          </button>
        ) : null}
      </div>

      <div className="panel">
        <h3>📋 Recent Proposals</h3>
        {DEMO_PROPOSALS.map((p) => (
          <div key={p.id} className="proposal-item">
            <div className="proposal-header">
              <span>{p.description}</span>
              <span className={`badge state-${p.state}`}>{PROPOSAL_STATE[p.state]}</span>
            </div>
            {p.state === 1 && (
              <div className="vote-actions">
                <select onChange={(e) => setSupport(Number(e.target.value))} value={support}>
                  <option value={1}>For</option>
                  <option value={0}>Against</option>
                  <option value={2}>Abstain</option>
                </select>
                <button onClick={() => { setVotingId(p.id); handleVote(); }} disabled={isPending} className="btn-small">
                  Vote
                </button>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
