// vault.ts
import { FeeForwarded, Deposit, Withdraw } from "../generated/FeeVault/FeeVault";
import { FeeVault as FeeVaultContract }     from "../generated/FeeVault/FeeVault";
import { FeeEvent, VaultSnapshot }          from "../generated/schema";
import { BigInt }                           from "@graphprotocol/graph-ts";

export function handleFeeForwarded(event: FeeForwarded): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let fee = new FeeEvent(id);
  fee.source      = event.params.source;
  fee.amount      = event.params.amount;
  fee.timestamp   = event.block.timestamp;
  fee.blockNumber = event.block.number;
  fee.txHash      = event.transaction.hash;
  fee.save();
}

function _snapshot(event: ethereum.Event): void {
  let vault    = FeeVaultContract.bind(event.address);
  let snap     = new VaultSnapshot(event.block.number.toString());
  snap.totalAssets  = vault.totalAssets();
  snap.totalShares  = vault.totalSupply();
  snap.timestamp    = event.block.timestamp;
  snap.blockNumber  = event.block.number;
  snap.save();
}

export function handleVaultDeposit(event: Deposit): void  { _snapshot(event); }
export function handleVaultWithdraw(event: Withdraw): void { _snapshot(event); }

import { ethereum } from "@graphprotocol/graph-ts";
