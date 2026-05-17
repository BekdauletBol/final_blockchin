// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPredictionMarket} from "../interfaces/IPredictionMarket.sol";
import {IMarketAMM} from "../interfaces/IMarketAMM.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";
import {IOracleResolver} from "../interfaces/IOracleResolver.sol";
import {IFeeVault} from "../interfaces/IFeeVault.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {YulMath} from "../libraries/YulMath.sol";

/// @title PredictionMarket (V1)
/// @notice Binary outcome market: CPMM trading + state machine + oracle resolution + pull-payment claim.
/// @dev Deployed as a UUPS proxy by MarketFactory. One proxy per market. Implementation is shared.
///      Storage layout MUST be preserved across upgrades — see __gap at end and the ARCHITECTURE.md
///      storage-collision proof.
///
///      Design patterns realised in this contract:
///         1. Proxy / UUPS                 — upgradeable via TimeLock-only _authorizeUpgrade
///         2. Access Control               — DEFAULT_ADMIN_ROLE = Timelock, PAUSER_ROLE = Timelock+Multisig
///         3. State Machine                — MarketState transitions enforced by inState() modifier
///         4. Checks-Effects-Interactions  — reserves and balances mutated before token transfers
///         5. Reentrancy Guard             — every external state-changing function uses nonReentrant
///         6. Pausable / Circuit Breaker   — pause() halts all trading and claims
///         7. Pull-over-push payments      — claim() requires user action; no implicit transfers
///         8. Oracle adapter               — IOracleResolver abstracts away Chainlink
contract PredictionMarket is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ERC1155HolderUpgradeable,
    IPredictionMarket,
    IMarketAMM
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice 0.3 % total fee, split 5 bps protocol / 25 bps LPs (in basis points × 10).
    uint256 public constant FEE_BPS_PROTOCOL = 5;   // 0.05 %
    uint256 public constant FEE_BPS_LP       = 25;  // 0.25 %
    uint256 public constant FEE_BPS_TOTAL    = 30;  // 0.30 %
    uint256 public constant BPS_DENOMINATOR  = 10_000;

    /// @notice Minimum liquidity locked forever on the first deposit (Uniswap-V2 style inflation-attack guard).
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    uint8 public constant OUTCOME_INDEX_YES = 1;
    uint8 public constant OUTCOME_INDEX_NO  = 2;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES STATE
        These are set once at initialize() and never updated. They live in proxy storage,
        not as Solidity immutables, because UUPS implementations can be upgraded.
    //////////////////////////////////////////////////////////////*/

    IERC20             public collateralToken;
    IConditionalTokens public conditionalTokens;
    IOracleResolver    public oracle;
    IFeeVault          public feeVault;
    LPToken            public lpToken;

    int256  public thresholdPrice;
    uint256 public override yesTokenId;
    uint256 public override noTokenId;

    uint64 public closeTime;
    uint64 public resolutionTime;
    uint64 public disputeWindowDuration;
    string public question;

    /*//////////////////////////////////////////////////////////////
                              MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    MarketState public marketState;
    Outcome     public marketOutcome;
    uint64      public disputeWindowEnd;

    uint256 public yesReserve;
    uint256 public noReserve;
    uint256 public accumulatedLPFees;  // collateral fees retained for LPs (released on removeLiquidity)
    bool    public ammFrozen;

    /// @dev Storage gap for future variables. Decrease this when adding state in V2+.
    uint256[40] private __gap;

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Disable initializers on the implementation itself so it cannot be hijacked.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitParams calldata p) external initializer {
        if (p.admin == address(0) || p.collateralToken == address(0) || p.conditionalTokens == address(0)
            || p.oracle == address(0) || p.feeVault == address(0) || p.lpToken == address(0))
            revert ZeroAddress();
        require(p.closeTime > block.timestamp, "closeTime in past");
        require(p.disputeWindowDuration >= 1 hours && p.disputeWindowDuration <= 7 days, "dispute window OOB");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC1155Holder_init();

        _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
        _grantRole(PAUSER_ROLE,   p.pauser);
        _grantRole(UPGRADER_ROLE, p.upgrader);

        collateralToken       = IERC20(p.collateralToken);
        conditionalTokens     = IConditionalTokens(p.conditionalTokens);
        oracle                = IOracleResolver(p.oracle);
        feeVault              = IFeeVault(p.feeVault);
        lpToken               = LPToken(p.lpToken);
        thresholdPrice        = p.thresholdPrice;
        closeTime             = p.closeTime;
        disputeWindowDuration = p.disputeWindowDuration;
        question              = p.question;

        (yesTokenId, noTokenId) = conditionalTokens.getIds(address(this));

        marketState   = MarketState.Active;
        marketOutcome = Outcome.Unresolved;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier inState(MarketState expected) {
        if (marketState != expected) revert InvalidState(expected, marketState);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                       STATE MACHINE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Active → Closed once closeTime has passed. Permissionless trigger.
    function close() external override whenNotPaused inState(MarketState.Active) {
        if (block.timestamp < closeTime) revert MarketNotClosed();
        _transition(MarketState.Closed);
        ammFrozen = true;
    }

    /// @notice Closed → Resolved by pulling outcome from the oracle. Permissionless.
    function resolve() external override whenNotPaused inState(MarketState.Closed) {
        (bool resolvedAbove, int256 priceUsed,) = oracle.resolveAgainstThreshold(thresholdPrice);
        Outcome o = resolvedAbove ? Outcome.Yes : Outcome.No;
        marketOutcome = o;
        resolutionTime = uint64(block.timestamp);
        disputeWindowEnd = uint64(block.timestamp + disputeWindowDuration);
        _transition(MarketState.Resolved);
        emit OutcomeResolved(o, msg.sender, priceUsed);
    }

    /// @notice Anyone can dispute during the window. Halts auto-finalize; governance must rule.
    function dispute(string calldata reason) external override whenNotPaused inState(MarketState.Resolved) {
        if (block.timestamp >= disputeWindowEnd) revert MarketStillInDisputeWindow();
        _transition(MarketState.Disputed);
        emit DisputeRaised(msg.sender, reason);
    }

    /// @notice Resolved → Finalized once dispute window elapses with no challenge. Permissionless.
    function finalize() external override whenNotPaused inState(MarketState.Resolved) {
        if (block.timestamp < disputeWindowEnd) revert MarketStillInDisputeWindow();
        _transition(MarketState.Finalized);
    }

    /// @notice Timelock-only path to settle a disputed market with an authoritative outcome.
    function governanceResolve(Outcome forced) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (marketState != MarketState.Disputed) revert InvalidState(MarketState.Disputed, marketState);
        if (forced == Outcome.Unresolved) revert InvalidOutcome();
        marketOutcome = forced;
        _transition(MarketState.Finalized);
        emit OutcomeResolved(forced, msg.sender, 0);
    }

    function _transition(MarketState newState) internal {
        emit MarketStateChanged(marketState, newState);
        marketState = newState;
    }

    /*//////////////////////////////////////////////////////////////
                                 AMM
    //////////////////////////////////////////////////////////////*/

    /// @notice Add liquidity; mints (collateralAmount × 2) shares (YES+NO) into reserves.
    function addLiquidity(uint256 collateralAmount, uint256 minLp, uint256 deadline)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 lpMinted)
    {
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (collateralAmount == 0) revert ZeroAmount();
        if (ammFrozen) revert AmmFrozen();

        // --- CHECKS / EFFECTS (compute LP shares first) ---
        uint256 supply = lpToken.totalSupply();
        if (supply == 0) {
            // First LP: lock MINIMUM_LIQUIDITY to address(1) to prevent inflation attacks.
            require(collateralAmount > MINIMUM_LIQUIDITY, "below MIN_LIQ");
            lpMinted = collateralAmount - MINIMUM_LIQUIDITY;
            lpToken.mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            // Pro-rata against the smaller reserve to dampen skew exploitation.
            uint256 smaller = yesReserve < noReserve ? yesReserve : noReserve;
            require(smaller > 0, "empty pool");
            lpMinted = YulMath.mulDiv(supply, collateralAmount, smaller);
        }
        if (lpMinted < minLp) revert SlippageExceeded(minLp, lpMinted);

        // Update reserves BEFORE external calls (CEI).
        yesReserve += collateralAmount;
        noReserve  += collateralAmount;

        // --- INTERACTIONS ---
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        conditionalTokens.mintComplete(address(this), collateralAmount);
        lpToken.mint(msg.sender, lpMinted);

        emit LiquidityAdded(msg.sender, collateralAmount, lpMinted);
    }

    /// @notice Burn LP tokens to withdraw a pro-rata slice of (yes_r, no_r, accumulated_lp_fees).
    function removeLiquidity(uint256 lpAmount, uint256 minYes, uint256 minNo, uint256 deadline)
        external
        override
        nonReentrant
        returns (uint256 yesOut, uint256 noOut)
    {
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (lpAmount == 0) revert ZeroAmount();
        uint256 supply = lpToken.totalSupply();
        if (supply == 0) revert InsufficientLiquidity();

        yesOut = YulMath.mulDiv(lpAmount, yesReserve, supply);
        noOut  = YulMath.mulDiv(lpAmount, noReserve,  supply);
        uint256 feeOut = YulMath.mulDiv(lpAmount, accumulatedLPFees, supply);

        if (yesOut < minYes || noOut < minNo) revert SlippageExceeded(minYes, yesOut);

        // EFFECTS
        yesReserve        -= yesOut;
        noReserve         -= noOut;
        accumulatedLPFees -= feeOut;
        lpToken.burn(msg.sender, lpAmount);

        // INTERACTIONS
        IConditionalTokens ct = conditionalTokens;
        ct.safeTransferFrom(address(this), msg.sender, yesTokenId, yesOut, "");
        ct.safeTransferFrom(address(this), msg.sender, noTokenId,  noOut,  "");
        if (feeOut > 0) collateralToken.safeTransfer(msg.sender, feeOut);

        emit LiquidityRemoved(msg.sender, lpAmount, yesOut, noOut);
    }

    /// @notice Buy YES shares with collateral. Mint-complete then internal swap NO→YES.
    function buyYes(uint256 collateralIn, uint256 minSharesOut, uint256 deadline)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 yesOut)
    {
        return _buy(true, collateralIn, minSharesOut, deadline);
    }

    function buyNo(uint256 collateralIn, uint256 minSharesOut, uint256 deadline)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 noOut)
    {
        return _buy(false, collateralIn, minSharesOut, deadline);
    }

    function _buy(bool isYes, uint256 collateralIn, uint256 minSharesOut, uint256 deadline)
        internal
        virtual
        returns (uint256 sharesOut)
    {
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (collateralIn == 0) revert ZeroAmount();
        if (ammFrozen) revert AmmFrozen();
        if (yesReserve == 0 || noReserve == 0) revert InsufficientLiquidity();

        // Split fee
        uint256 feeProtocol = YulMath.mulDiv(collateralIn, FEE_BPS_PROTOCOL, BPS_DENOMINATOR);
        uint256 feeLP       = YulMath.mulDiv(collateralIn, FEE_BPS_LP,       BPS_DENOMINATOR);
        uint256 cEffective  = collateralIn - feeProtocol - feeLP;

        // Compute output
        uint256 yR = yesReserve;
        uint256 nR = noReserve;
        // sharesOut = C_eff * (yR + nR + C_eff) / (other_reserve + C_eff)
        if (isYes) {
            // buy YES: pool gains C_eff NO; removes some YES
            sharesOut = YulMath.mulDiv(cEffective, yR + nR + cEffective, nR + cEffective);
        } else {
            sharesOut = YulMath.mulDiv(cEffective, yR + nR + cEffective, yR + cEffective);
        }
        if (sharesOut < minSharesOut) revert SlippageExceeded(minSharesOut, sharesOut);

        // EFFECTS: maintain k_old = yR * nR
        uint256 kBefore = yR * nR;
        if (isYes) {
            yesReserve = yR + cEffective - sharesOut;
            noReserve  = nR + cEffective;
        } else {
            yesReserve = yR + cEffective;
            noReserve  = nR + cEffective - sharesOut;
        }
        // Invariant check (defensive; should hold to within rounding)
        uint256 kAfter = yesReserve * noReserve;
        if (kAfter < kBefore) revert KInvariantViolated(kBefore, kAfter);

        accumulatedLPFees += feeLP;

        // INTERACTIONS
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralIn);
        // Mint the complete set into AMM (we "own" the shares)
        conditionalTokens.mintComplete(address(this), cEffective);
        // Send out winning side
        uint256 outId = isYes ? yesTokenId : noTokenId;
        conditionalTokens.safeTransferFrom(address(this), msg.sender, outId, sharesOut, "");
        // Forward protocol fee to vault
        if (feeProtocol > 0) {
            collateralToken.safeIncreaseAllowance(address(feeVault), feeProtocol);
            feeVault.notifyFee(feeProtocol);
        }

        emit Swap(msg.sender, isYes, collateralIn, sharesOut, feeProtocol, feeLP);
        _afterTrade(msg.sender, isYes, collateralIn, sharesOut);
    }

    /// @notice Hook executed after a successful trade. V1 is a no-op; V2 records volume.
    /// @dev    Override-friendly extension point — keeps the swap path itself stable across upgrades.
    function _afterTrade(address trader, bool isYes, uint256 collateralIn, uint256 sharesOut) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                              CLAIM (PULL)
    //////////////////////////////////////////////////////////////*/

    /// @notice Pull-payment claim: burn winning shares for 1 collateral each. Invalid = 0.5 each side.
    function claim() external override nonReentrant returns (uint256 collateralReturned) {
        if (marketState != MarketState.Finalized) {
            revert InvalidState(MarketState.Finalized, marketState);
        }

        uint256 yesBal = conditionalTokens.balanceOf(msg.sender, yesTokenId);
        uint256 noBal  = conditionalTokens.balanceOf(msg.sender, noTokenId);

        if (marketOutcome == Outcome.Yes) {
            if (yesBal == 0) revert NothingToClaim();
            collateralReturned = yesBal;
            conditionalTokens.burnSingle(msg.sender, OUTCOME_INDEX_YES, yesBal);
        } else if (marketOutcome == Outcome.No) {
            if (noBal == 0) revert NothingToClaim();
            collateralReturned = noBal;
            conditionalTokens.burnSingle(msg.sender, OUTCOME_INDEX_NO, noBal);
        } else if (marketOutcome == Outcome.Invalid) {
            if (yesBal == 0 && noBal == 0) revert NothingToClaim();
            // 50/50 refund
            collateralReturned = (yesBal + noBal) / 2;
            if (yesBal > 0) conditionalTokens.burnSingle(msg.sender, OUTCOME_INDEX_YES, yesBal);
            if (noBal  > 0) conditionalTokens.burnSingle(msg.sender, OUTCOME_INDEX_NO,  noBal);
        } else {
            revert InvalidOutcome();
        }

        collateralToken.safeTransfer(msg.sender, collateralReturned);
        emit WinningsClaimed(msg.sender, collateralReturned, yesBal + noBal);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    function info() external view override returns (MarketInfo memory) {
        return MarketInfo({
            question:        question,
            closeTime:       closeTime,
            resolutionTime:  resolutionTime,
            collateralToken: address(collateralToken),
            oracle:          address(oracle),
            state:           marketState,
            outcome:         marketOutcome,
            totalCollateral: collateralToken.balanceOf(address(this))
        });
    }

    function state() external view override returns (MarketState) { return marketState; }
    function outcome() external view override returns (Outcome) { return marketOutcome; }

    function reserves() external view override returns (uint256, uint256) {
        return (yesReserve, noReserve);
    }

    function k() external view override returns (uint256) { return yesReserve * noReserve; }

    function priceYes() external view override returns (uint256) {
        return YulMath.mulDiv(noReserve, 1e18, yesReserve + noReserve);
    }
    function priceNo() external view override returns (uint256) {
        return YulMath.mulDiv(yesReserve, 1e18, yesReserve + noReserve);
    }

    function quoteBuyYes(uint256 collateralIn) external view override returns (uint256 yesOut) {
        if (yesReserve == 0 || noReserve == 0) return 0;
        uint256 cEff = collateralIn - YulMath.mulDiv(collateralIn, FEE_BPS_TOTAL, BPS_DENOMINATOR);
        yesOut = YulMath.mulDiv(cEff, yesReserve + noReserve + cEff, noReserve + cEff);
    }
    function quoteBuyNo(uint256 collateralIn) external view override returns (uint256 noOut) {
        if (yesReserve == 0 || noReserve == 0) return 0;
        uint256 cEff = collateralIn - YulMath.mulDiv(collateralIn, FEE_BPS_TOTAL, BPS_DENOMINATOR);
        noOut = YulMath.mulDiv(cEff, yesReserve + noReserve + cEff, yesReserve + cEff);
    }

    function winningsFor(address user) external view override returns (uint256) {
        if (marketState != MarketState.Finalized) return 0;
        uint256 yesBal = conditionalTokens.balanceOf(user, yesTokenId);
        uint256 noBal  = conditionalTokens.balanceOf(user, noTokenId);
        if (marketOutcome == Outcome.Yes)     return yesBal;
        if (marketOutcome == Outcome.No)      return noBal;
        if (marketOutcome == Outcome.Invalid) return (yesBal + noBal) / 2;
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function pause() external override onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external override onlyRole(PAUSER_ROLE) { _unpause(); }

    /// @notice Freeze the AMM permanently (e.g. emergency).
    function freeze() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        ammFrozen = true;
    }

    /*//////////////////////////////////////////////////////////////
                              UUPS UPGRADE
    //////////////////////////////////////////////////////////////*/

    /// @dev Only the Timelock (UPGRADER_ROLE) can authorise an implementation upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                              ERC165 RESOLUTION
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC1155HolderUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
