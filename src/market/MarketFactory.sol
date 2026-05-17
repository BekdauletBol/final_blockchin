// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {PredictionMarket} from "./PredictionMarket.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IPredictionMarket} from "../interfaces/IPredictionMarket.sol";

/// @title MarketFactory
/// @notice Deploys PredictionMarket proxies and their companion LPTokens.
/// @dev Deliberately demonstrates BOTH CREATE patterns required by the spec:
///        - CREATE2 for the market proxy (deterministic address; lets dApps precompute the address).
///        - CREATE  for the per-market LPToken (no determinism needed; cheaper).
///
///      Access control: only CREATOR_ROLE may deploy new markets. In production this should be
///      the Timelock so market parameters pass through governance review. For bootstrap and tests
///      it can be the deployer.
contract MarketFactory is AccessControl {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pinned UUPS implementation. Upgraded by Timelock via PredictionMarket._authorizeUpgrade.
    address public immutable implementation;

    address public immutable conditionalTokens;
    address public immutable feeVault;
    address public immutable timelock;
    address public immutable pauser;

    address[] public allMarkets;
    mapping(bytes32 salt => address market) public marketBySalt;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(
        address indexed market,
        address indexed lpToken,
        address indexed oracle,
        bytes32 salt,
        int256 thresholdPrice,
        uint64 closeTime,
        string question
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SaltAlreadyUsed();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address implementation_,
        address conditionalTokens_,
        address feeVault_,
        address timelock_,
        address pauser_,
        address admin_,
        address bootstrapCreator_
    ) {
        if (
            implementation_ == address(0) || conditionalTokens_ == address(0) || feeVault_ == address(0)
                || timelock_ == address(0) || pauser_ == address(0) || admin_ == address(0)
        ) {
            revert ZeroAddress();
        }

        implementation = implementation_;
        conditionalTokens = conditionalTokens_;
        feeVault = feeVault_;
        timelock = timelock_;
        pauser = pauser_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(CREATOR_ROLE, bootstrapCreator_);
        // Production handover: Timelock should also hold CREATOR_ROLE so DAO proposals can mint markets.
        _grantRole(CREATOR_ROLE, timelock_);
    }

    /*//////////////////////////////////////////////////////////////
                              CREATE MARKET
    //////////////////////////////////////////////////////////////*/

    struct CreateParams {
        address collateralToken;
        address oracle;
        int256 thresholdPrice;
        uint64 closeTime;
        uint64 disputeWindowDuration;
        string question;
        string lpName;
        string lpSymbol;
        bytes32 salt;
    }

    /// @notice Deploy a new market. Two contracts are created here:
    ///           1. PredictionMarket proxy (CREATE2 — deterministic address).
    ///           2. LPToken (CREATE — cheaper, no determinism required).
    function createMarket(CreateParams calldata p)
        external
        onlyRole(CREATOR_ROLE)
        returns (address market, address lpTokenAddr)
    {
        if (marketBySalt[p.salt] != address(0)) revert SaltAlreadyUsed();

        // --- 1. CREATE2: deploy the UUPS proxy at a deterministic address. ---
        // Initialiser data is empty; we initialise AFTER LPToken deployment so we can
        // pass its address.  The market is *uninitialized* between these two steps —
        // safe because no external code holds its address yet.
        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, bytes("")));
        market = Create2.deploy(0, p.salt, creationCode);

        // Pre-register the market in ConditionalTokens (also CREATE-style step).
        IConditionalTokens(conditionalTokens).prepareCondition(market);

        // --- 2. CREATE: deploy the LP token bound to this market. ---
        LPToken lpToken = new LPToken(market, p.lpName, p.lpSymbol);
        lpTokenAddr = address(lpToken);

        // --- Now initialise the proxy. ---
        PredictionMarket(market)
            .initialize(
                IPredictionMarket.InitParams({
                admin: timelock,
                pauser: pauser,
                upgrader: timelock,
                collateralToken: p.collateralToken,
                conditionalTokens: conditionalTokens,
                oracle: p.oracle,
                feeVault: feeVault,
                lpToken: lpTokenAddr,
                thresholdPrice: p.thresholdPrice,
                closeTime: p.closeTime,
                disputeWindowDuration: p.disputeWindowDuration,
                question: p.question
            })
            );

        marketBySalt[p.salt] = market;
        allMarkets.push(market);
        emit MarketCreated(market, lpTokenAddr, p.oracle, p.salt, p.thresholdPrice, p.closeTime, p.question);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    /// @notice Compute the CREATE2 address of a market before deployment.
    /// @dev Useful for the dApp to pre-display a market URL while the proposal is in voting.
    function predictMarketAddress(bytes32 salt) external view returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, bytes("")));
        return Create2.computeAddress(salt, keccak256(creationCode), address(this));
    }
}
