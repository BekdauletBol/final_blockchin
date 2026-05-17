// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPredictionMarket
/// @notice Public interface for a single binary prediction market instance.
/// @dev Each market is a UUPS proxy. Lifecycle: Active → Closed → Resolved → Finalized.
interface IPredictionMarket {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    enum MarketState {
        Active, // Trading open, before closeTime
        Closed, // Past closeTime, awaiting oracle resolution
        Resolved, // Oracle has supplied an outcome, dispute window running
        Disputed, // A dispute was raised — governance must resolve
        Finalized // Outcome locked, winners may claim
    }

    enum Outcome {
        Unresolved,
        Yes,
        No,
        Invalid // For markets resolved as invalid (50/50 refund)
    }

    struct MarketInfo {
        string question;
        uint256 closeTime;
        uint256 resolutionTime;
        address collateralToken;
        address oracle;
        MarketState state;
        Outcome outcome;
        uint256 totalCollateral;
    }

    struct InitParams {
        address admin; // Timelock
        address pauser; // multisig
        address upgrader; // Timelock
        address collateralToken;
        address conditionalTokens;
        address oracle;
        address feeVault;
        address lpToken;
        int256 thresholdPrice;
        uint64 closeTime;
        uint64 disputeWindowDuration;
        string question;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketStateChanged(MarketState indexed oldState, MarketState indexed newState);
    event OutcomeResolved(Outcome indexed outcome, address indexed resolver, int256 oraclePrice);
    event DisputeRaised(address indexed disputer, string reason);
    event WinningsClaimed(address indexed user, uint256 collateralReturned, uint256 sharesBurned);
    event CollateralWithdrawn(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidState(MarketState expected, MarketState actual);
    error MarketNotClosed();
    error MarketStillInDisputeWindow();
    error OracleStale(uint256 updatedAt, uint256 staleness);
    error InvalidOutcome();
    error NothingToClaim();
    error NotAuthorized();
    error ZeroAddress();
    error ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function info() external view returns (MarketInfo memory);
    function state() external view returns (MarketState);
    function outcome() external view returns (Outcome);
    function yesTokenId() external view returns (uint256);
    function noTokenId() external view returns (uint256);
    function winningsFor(address user) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function close() external;
    function resolve() external;
    function dispute(string calldata reason) external;
    function finalize() external;
    function claim() external returns (uint256 collateralReturned);

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function governanceResolve(Outcome forced) external;
    function pause() external;
    function unpause() external;
}
