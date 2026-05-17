// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LPToken
/// @notice Per-market ERC20 representing liquidity provider share in a PredictionMarket.
/// @dev Deployed via CREATE by MarketFactory (one per market) — pairs with a CREATE2-deployed market proxy.
///      Only the owning market can mint and burn.
contract LPToken is ERC20 {
    address public immutable market;

    error OnlyMarket();

    /// @param market_  The PredictionMarket that exclusively controls mint/burn.
    /// @param name_    e.g. "Prediction LP: ETH > $4000 by Dec 2026"
    /// @param symbol_  e.g. "PRED-LP-1"
    constructor(address market_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        require(market_ != address(0), "Zero market");
        market = market_;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert OnlyMarket();
        _;
    }

    function mint(address to, uint256 amount) external onlyMarket {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMarket {
        _burn(from, amount);
    }
}
