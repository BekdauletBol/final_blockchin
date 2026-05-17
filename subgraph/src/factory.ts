import { MarketCreated } from "../generated/MarketFactory/MarketFactory";
import { PredictionMarket as PredictionMarketTemplate } from "../generated/templates";
import { PredictionMarket as PredictionMarketContract } from "../generated/templates/PredictionMarket/PredictionMarket";
import { Market } from "../generated/schema";
import { BigInt, Bytes, log } from "@graphprotocol/graph-ts";

export function handleMarketCreated(event: MarketCreated): void {
  let id = event.params.market.toHexString();
  let market = new Market(id);

  // Bind the contract to read on-chain state
  let contract = PredictionMarketContract.bind(event.params.market);

  let infoResult = contract.try_info();
  if (infoResult.reverted) {
    log.warning("Market info() reverted for {}", [id]);
    return;
  }

  let info = infoResult.value;

  market.question           = info.question;
  market.collateralToken    = info.collateralToken;
  market.oracle             = info.oracle;
  market.thresholdPrice     = contract.thresholdPrice();
  market.closeTime          = BigInt.fromI32(info.closeTime as i32);
  market.state              = 0; // Active
  market.outcome            = 0; // Unresolved
  market.yesTokenId         = contract.yesTokenId();
  market.noTokenId          = contract.noTokenId();
  market.lpToken            = event.params.lpToken;
  market.yesReserve         = BigInt.zero();
  market.noReserve          = BigInt.zero();
  market.totalCollateralIn  = BigInt.zero();
  market.totalFeesProtocol  = BigInt.zero();
  market.totalFeesLP        = BigInt.zero();
  market.totalLPMinted      = BigInt.zero();
  market.createdAtBlock     = event.block.number;
  market.createdAtTimestamp = event.block.timestamp;

  market.save();

  // Start tracking this market's events via the template
  PredictionMarketTemplate.create(event.params.market);

  log.info("Market created: {} — {}", [id, info.question]);
}
