// governance.ts
import { Transfer, DelegateChanged } from "../generated/GovernanceToken/GovernanceToken";
import { TokenHolder } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";

export function handleTransfer(event: Transfer): void {
  _updateHolder(event.params.from.toHexString(), event.block.timestamp);
  _updateHolder(event.params.to.toHexString(), event.block.timestamp);
}

export function handleDelegateChanged(event: DelegateChanged): void {
  let holder = _loadOrCreate(event.params.delegator.toHexString(), event.block.timestamp);
  holder.delegateTo = event.params.toDelegate;
  holder.save();
}

function _loadOrCreate(id: string, ts: BigInt): TokenHolder {
  let h = TokenHolder.load(id);
  if (!h) { h = new TokenHolder(id); h.balance = BigInt.zero(); h.votingPower = BigInt.zero(); }
  h.updatedAt = ts;
  return h as TokenHolder;
}

function _updateHolder(id: string, ts: BigInt): void {
  let h = _loadOrCreate(id, ts);
  h.save();
}
