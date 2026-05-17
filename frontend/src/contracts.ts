// Auto-generated from deployments/arbitrum-sepolia.json — update after each deploy

export const ADDRESSES = {
  govToken:          "0x316E03b1C406540068012c9eDad8A4A03e3BB533" as `0x${string}`,
  timelock:          "0x72D44a58D9ede9cAFB4A9EE35724B16EB46c1497" as `0x${string}`,
  governor:          "0x830320185c88D16C94FCd8C497745C812fF423eB" as `0x${string}`,
  conditionalTokens: "0xbc41495a062956b40BB96aa21d57C2E010eAF1EF" as `0x${string}`,
  feeVault:          "0xA890E97Ef006C0388B62B190a6cFf199181b781F" as `0x${string}`,
  factory:           "0x680B59b93dc038530D839755C42D4dA19f9F2893" as `0x${string}`,
  market1:           "0xAa4e61D30A32775123a997d805332eB6f63351CC" as `0x${string}`,
} as const;

// ─── Minimal ABIs (only functions needed by the frontend) ────────────────────

export const MARKET_ABI = [
  { name: "buyYes",          type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "collateralIn", type: "uint256" }, { name: "minSharesOut", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "buyNo",           type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "collateralIn", type: "uint256" }, { name: "minSharesOut", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "addLiquidity",    type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "collateralAmount", type: "uint256" }, { name: "minLp", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "claim",           type: "function", stateMutability: "nonpayable",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "reserves",        type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "yesReserve", type: "uint256" }, { name: "noReserve", type: "uint256" }] },
  { name: "priceYes",        type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "priceNo",         type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "quoteBuyYes",     type: "function", stateMutability: "view",
    inputs:  [{ name: "collateralIn", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "quoteBuyNo",      type: "function", stateMutability: "view",
    inputs:  [{ name: "collateralIn", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "state",           type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint8" }] },
  { name: "outcome",         type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint8" }] },
  { name: "winningsFor",     type: "function", stateMutability: "view",
    inputs:  [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "info",            type: "function", stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "tuple",
      components: [
        { name: "question",       type: "string"  },
        { name: "closeTime",      type: "uint256" },
        { name: "resolutionTime", type: "uint256" },
        { name: "collateralToken", type: "address" },
        { name: "oracle",         type: "address" },
        { name: "state",          type: "uint8"   },
        { name: "outcome",        type: "uint8"   },
        { name: "totalCollateral", type: "uint256" },
      ]
    }] },
  { name: "yesTokenId",      type: "function", stateMutability: "view",
    inputs:  [], outputs: [{ name: "", type: "uint256" }] },
  { name: "noTokenId",       type: "function", stateMutability: "view",
    inputs:  [], outputs: [{ name: "", type: "uint256" }] },
  { name: "close",           type: "function", stateMutability: "nonpayable",
    inputs:  [], outputs: [] },
  { name: "resolve",         type: "function", stateMutability: "nonpayable",
    inputs:  [], outputs: [] },
  { name: "finalize",        type: "function", stateMutability: "nonpayable",
    inputs:  [], outputs: [] },
] as const;

export const GOV_TOKEN_ABI = [
  { name: "balanceOf",     type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "getVotes",      type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "delegates",     type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "address" }] },
  { name: "delegate",      type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "delegatee", type: "address" }],
    outputs: [] },
  { name: "approve",       type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }] },
] as const;

export const GOVERNOR_ABI = [
  { name: "propose",       type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "targets", type: "address[]" }, { name: "values", type: "uint256[]" },
              { name: "calldatas", type: "bytes[]" }, { name: "description", type: "string" }],
    outputs: [{ name: "proposalId", type: "uint256" }] },
  { name: "castVote",      type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "proposalId", type: "uint256" }, { name: "support", type: "uint8" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "queue",         type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "targets", type: "address[]" }, { name: "values", type: "uint256[]" },
              { name: "calldatas", type: "bytes[]" }, { name: "descriptionHash", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "execute",       type: "function", stateMutability: "payable",
    inputs:  [{ name: "targets", type: "address[]" }, { name: "values", type: "uint256[]" },
              { name: "calldatas", type: "bytes[]" }, { name: "descriptionHash", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "state",         type: "function", stateMutability: "view",
    inputs:  [{ name: "proposalId", type: "uint256" }],
    outputs: [{ name: "", type: "uint8" }] },
  { name: "proposalVotes", type: "function", stateMutability: "view",
    inputs:  [{ name: "proposalId", type: "uint256" }],
    outputs: [{ name: "againstVotes", type: "uint256" }, { name: "forVotes", type: "uint256" }, { name: "abstainVotes", type: "uint256" }] },
] as const;

export const ERC20_ABI = [
  { name: "balanceOf", type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }], outputs: [{ name: "", type: "uint256" }] },
  { name: "approve",   type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }] },
] as const;

export const CONDITIONAL_TOKENS_ABI = [
  { name: "balanceOf", type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }, { name: "id", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }] },
  { name: "setApprovalForAll", type: "function", stateMutability: "nonpayable",
    inputs:  [{ name: "operator", type: "address" }, { name: "approved", type: "bool" }],
    outputs: [] },
] as const;

export const VAULT_ABI = [
  { name: "totalAssets",    type: "function", stateMutability: "view",
    inputs:  [], outputs: [{ name: "", type: "uint256" }] },
  { name: "balanceOf",      type: "function", stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }], outputs: [{ name: "", type: "uint256" }] },
  { name: "convertToAssets",type: "function", stateMutability: "view",
    inputs:  [{ name: "shares", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
] as const;

// Proposal state enum labels
export const PROPOSAL_STATE: Record<number, string> = {
  0: "Pending", 1: "Active", 2: "Canceled", 3: "Defeated",
  4: "Succeeded", 5: "Queued", 6: "Expired", 7: "Executed",
};

export const MARKET_STATE: Record<number, string> = {
  0: "Active", 1: "Closed", 2: "Resolved", 3: "Disputed", 4: "Finalized",
};

export const MARKET_OUTCOME: Record<number, string> = {
  0: "Unresolved", 1: "YES wins", 2: "NO wins", 3: "Invalid",
};
