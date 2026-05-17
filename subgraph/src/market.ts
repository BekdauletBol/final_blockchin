import {
  Swap,
  LiquidityAdded,
  LiquidityRemoved,
  WinningsClaimed,
  OutcomeResolved,
  MarketStateChanged,
  DisputeRaised,
} from "../generated/templates/PredictionMarket/PredictionMarket";
import {
  Market,
  Swap as SwapEntity,
  LiquidityEvent,
  Claim,
  MarketResolution,
} from "../generated/schema";
import { BigInt, log } from "@graphprotocol/graph-ts";

// ── Swap ─────────────────────────────────────────────────────────────────────

export function handleSwap(event: Swap): void {
  let marketId = event.address.toHexString();
  let market = Market.load(marketId);
  if (!market) { log.warning("Unknown market on Swap: {}", [marketId]); return; }

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let swap = new SwapEntity(id);
  swap.market       = marketId;
  swap.trader       = event.params.trader;
  swap.isYes        = event.params.buyYes;
  swap.collateralIn = event.params.collateralIn;
  swap.sharesOut    = event.params.sharesOut;
  swap.feeProtocol  = event.params.feeToVault;
  swap.feeLP        = event.params.feeToLPs;
  swap.timestamp    = event.block.timestamp;
  swap.blockNumber  = event.block.number;
  swap.txHash       = event.transaction.hash;
  swap.save();

  // Update market aggregates
  market.totalCollateralIn = market.totalCollateralIn.plus(event.params.collateralIn);
  market.totalFeesProtocol = market.totalFeesProtocol.plus(event.params.feeToVault);
  market.totalFeesLP       = market.totalFeesLP.plus(event.params.feeToLPs);

  // Update reserves (recompute from event deltas: collateral minted as complete set)
  if (event.params.buyYes) {
    // yesReserve decreased by sharesOut; noReserve increased by effective collateral
    market.yesReserve = market.yesReserve.minus(event.params.sharesOut);
    market.noReserve  = market.noReserve.plus(event.params.collateralIn
      .minus(event.params.feeToVault)
      .minus(event.params.feeToLPs));
  } else {
    market.noReserve  = market.noReserve.minus(event.params.sharesOut);
    market.yesReserve = market.yesReserve.plus(event.params.collateralIn
      .minus(event.params.feeToVault)
      .minus(event.params.feeToLPs));
  }
  market.save();
}

// ── Liquidity Added ───────────────────────────────────────────────────────────

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let marketId = event.address.toHexString();
  let market = Market.load(marketId);
  if (!market) return;

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liqEvent = new LiquidityEvent(id);
  liqEvent.market       = marketId;
  liqEvent.provider     = event.params.provider;
  liqEvent.type         = "add";
  liqEvent.collateralIn = event.params.collateralIn;
  liqEvent.lpTokens     = event.params.lpMinted;
  liqEvent.timestamp    = event.block.timestamp;
  liqEvent.blockNumber  = event.block.number;
  liqEvent.txHash       = event.transaction.hash;
  liqEvent.save();

  market.yesReserve       = market.yesReserve.plus(event.params.collateralIn);
  market.noReserve        = market.noReserve.plus(event.params.collateralIn);
  market.totalCollateralIn = market.totalCollateralIn.plus(event.params.collateralIn);
  market.totalLPMinted     = market.totalLPMinted.plus(event.params.lpMinted);
  market.save();
}

// ── Liquidity Removed ─────────────────────────────────────────────────────────

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let marketId = event.address.toHexString();
  let market = Market.load(marketId);
  if (!market) return;

  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liqEvent = new LiquidityEvent(id);
  liqEvent.market      = marketId;
  liqEvent.provider    = event.params.provider;
  liqEvent.type        = "remove";
  liqEvent.lpTokens    = event.params.lpBurned;
  liqEvent.yesOut      = event.params.yesOut;
  liqEvent.noOut       = event.params.noOut;
  liqEvent.timestamp   = event.block.timestamp;
  liqEvent.blockNumber = event.block.number;
  liqEvent.txHash      = event.transaction.hash;
  liqEvent.save();

  market.yesReserve = market.yesReserve.minus(event.params.yesOut);
  market.noReserve  = market.noReserve.minus(event.params.noOut);
  market.save();
}

// ── Claim ─────────────────────────────────────────────────────────────────────

export function handleClaimed(event: WinningsClaimed): void {
  let marketId = event.address.toHexString();
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let claim = new Claim(id);
  claim.market             = marketId;
  claim.claimer            = event.params.user;
  claim.collateralReturned = event.params.collateralReturned;
  claim.sharesBurned       = event.params.sharesBurned;
  claim.timestamp          = event.block.timestamp;
  claim.blockNumber        = event.block.number;
  claim.txHash             = event.transaction.hash;
  claim.save();
}

// ── Resolution ────────────────────────────────────────────────────────────────

export function handleResolved(event: OutcomeResolved): void {
  let marketId = event.address.toHexString();
  let market = Market.load(marketId);
  if (!market) return;

  market.outcome = event.params.outcome;
  market.save();

  let resolution = new MarketResolution(marketId);
  resolution.market      = marketId;
  resolution.outcome     = event.params.outcome;
  resolution.resolver    = event.params.resolver;
  resolution.oraclePrice = event.params.oraclePrice;
  resolution.timestamp   = event.block.timestamp;
  resolution.isDisputed  = false;
  resolution.save();
}

// ── State Changed ─────────────────────────────────────────────────────────────

export function handleStateChanged(event: MarketStateChanged): void {
  let market = Market.load(event.address.toHexString());
  if (!market) return;
  market.state = event.params.newState;
  market.save();
}

// ── Disputed ─────────────────────────────────────────────────────────────────

export function handleDisputed(event: DisputeRaised): void {
  let marketId = event.address.toHexString();
  let resolution = MarketResolution.load(marketId);
  if (!resolution) return;
  resolution.isDisputed    = true;
  resolution.disputer      = event.params.disputer;
  resolution.disputeReason = event.params.reason;
  resolution.save();
}
