// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title IConditionalTokens
/// @notice ERC-1155 outcome share tokens. Each market mints two token IDs (YES, NO).
/// @dev Token ID derivation: uint256(keccak256(abi.encode(marketAddress, outcomeIndex))).
///      mint/burn functions are gated on msg.sender being an authorised market.
interface IConditionalTokens is IERC1155 {
    event ConditionPrepared(address indexed market, uint256 yesId, uint256 noId);
    event SharesMintedComplete(address indexed market, address indexed to, uint256 amount);
    event SharesBurnedComplete(address indexed market, address indexed from, uint256 amount);
    event SharesBurnedSingle(address indexed market, address indexed from, uint8 outcomeIndex, uint256 amount);

    error NotAuthorizedMarket();
    error ConditionAlreadyPrepared();
    error InvalidOutcomeIndex(uint8 supplied);

    function prepareCondition(address market) external returns (uint256 yesId, uint256 noId);
    function mintComplete(address to, uint256 amount) external;
    function burnComplete(address from, uint256 amount) external;
    function burnSingle(address from, uint8 outcomeIndex, uint256 amount) external;

    function getIds(address market) external view returns (uint256 yesId, uint256 noId);
    function isAuthorizedMarket(address market) external view returns (bool);
}
