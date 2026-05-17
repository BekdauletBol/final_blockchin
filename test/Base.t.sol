// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy}   from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Protocol contracts
import {GovernanceToken}     from "src/governance/GovernanceToken.sol";
import {PredictionTimelock}  from "src/governance/PredictionTimelock.sol";
import {PredictionGovernor}  from "src/governance/PredictionGovernor.sol";
import {ConditionalTokens}   from "src/tokens/ConditionalTokens.sol";
import {LPToken}             from "src/tokens/LPToken.sol";
import {FeeVault}            from "src/vault/FeeVault.sol";
import {PredictionMarket}    from "src/market/PredictionMarket.sol";
import {PredictionMarketV2}  from "src/market/PredictionMarketV2.sol";
import {MarketFactory}       from "src/market/MarketFactory.sol";
import {ChainlinkResolver}   from "src/oracle/ChainlinkResolver.sol";
import {MockAggregator}      from "src/mocks/MockAggregator.sol";
import {MockERC20}           from "src/mocks/MockERC20.sol";

// Interfaces
import {IPredictionMarket}  from "src/interfaces/IPredictionMarket.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";

/// @notice Shared deploy + helper base for all tests in the prediction-market suite.
abstract contract Base is Test {
    /*//////////////////////////////////////////////////////////////
                              TEST ACTORS
    //////////////////////////////////////////////////////////////*/

    address internal deployer  = makeAddr("deployer");
    address internal alice     = makeAddr("alice");
    address internal bob       = makeAddr("bob");
    address internal carol     = makeAddr("carol");
    address internal multisig  = makeAddr("multisig");   // pauser role holder

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL CONTRACTS
    //////////////////////////////////////////////////////////////*/

    MockERC20            internal usdc;
    MockAggregator       internal aggregator;
    ChainlinkResolver    internal resolver;
    GovernanceToken      internal govToken;
    PredictionTimelock   internal timelock;
    PredictionGovernor   internal governor;
    ConditionalTokens    internal ct;
    FeeVault             internal vault;
    PredictionMarket     internal impl;     // bare implementation (no proxy)
    MarketFactory        internal factory;

    // Default market deployed in setUp()
    PredictionMarket     internal market;
    LPToken              internal lpToken;

    /*//////////////////////////////////////////////////////////////
                          MARKET PARAMETERS
    //////////////////////////////////////////////////////////////*/

    int256  internal constant THRESHOLD    = 3_000e8;   // $3 000 in 8-decimal Chainlink format
    int256  internal constant PRICE_ABOVE  = 3_500e8;   // resolves YES
    int256  internal constant PRICE_BELOW  = 2_500e8;   // resolves NO
    uint64  internal constant CLOSE_DELAY  = 7 days;
    uint64  internal constant DISPUTE_WIN  = 1 hours;
    uint256 internal constant INITIAL_LIQ  = 100_000e6; // 100 000 USDC

    // Standard amounts
    uint256 internal constant ONE_USDC     = 1e6;
    uint256 internal constant SWAP_AMOUNT  = 1_000e6;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.startPrank(deployer);

        // ── Collateral ──────────────────────────────────────────
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // ── Oracle (mock) ────────────────────────────────────────
        aggregator = new MockAggregator(PRICE_ABOVE, 8, "ETH/USD");
        resolver   = new ChainlinkResolver(aggregator, 1 hours, "ETH/USD Arbitrum");

        console2.log("Deploying GovernanceToken...");
        govToken = new GovernanceToken(deployer, deployer, 10_000_000e18);
        console2.logBytes32(govToken.DEFAULT_ADMIN_ROLE());
        console2.log("Deployer has role:", govToken.hasRole(govToken.DEFAULT_ADMIN_ROLE(), deployer));

        console2.log("Deploying Timelock...");
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new PredictionTimelock(2 days, proposers, executors, deployer);

        console2.log("Deploying Governor...");
        governor = new PredictionGovernor(govToken, timelock);

        console2.log("Granting Proposer role to Governor...");
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        console2.log("Granting Canceller role to Governor...");
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        console2.log("Renouncing Timelock admin...");
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        console2.log("Granting govToken admin to Timelock...");
        govToken.grantRole(govToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        govToken.grantRole(govToken.MINTER_ROLE(), address(timelock));
        govToken.revokeRole(govToken.DEFAULT_ADMIN_ROLE(), deployer);
        govToken.revokeRole(govToken.MINTER_ROLE(), deployer);

        // ── ConditionalTokens ────────────────────────────────────
        ct = new ConditionalTokens(address(timelock));

        // ── FeeVault ─────────────────────────────────────────────
        // Factory address not yet known; we deploy vault first and authorise factory after.
        vault = new FeeVault(usdc, address(timelock), deployer /* placeholder */);

        // ── PredictionMarket implementation ───────────────────────
        impl = new PredictionMarket();

        // ── Factory ───────────────────────────────────────────────
        factory = new MarketFactory(
            address(impl),
            address(ct),
            address(vault),
            address(timelock),
            multisig,
            deployer,        // admin (bootstrap)
            deployer         // bootstrapCreator
        );

        // Grant factory the FACTORY_ROLE on ConditionalTokens
        vm.stopPrank();
        vm.startPrank(deployer);
        // ConditionalTokens admin is Timelock — we bypass with a direct grant during test setup.
        // In production this would be a governance proposal.
        _grantTimelockRole(address(ct), ct.FACTORY_ROLE(), address(factory));

        // Authorise factory as a fee source
        _grantTimelockRole(address(vault), vault.SOURCE_ROLE(), address(factory));

        // ── Deploy default test market ────────────────────────────
        (address mktAddr, address lpAddr) = factory.createMarket(
            MarketFactory.CreateParams({
                collateralToken:       address(usdc),
                oracle:                address(resolver),
                thresholdPrice:        THRESHOLD,
                closeTime:             uint64(block.timestamp + CLOSE_DELAY),
                disputeWindowDuration: DISPUTE_WIN,
                question:              "Will ETH be above $3000 by next week?",
                lpName:                "PredMarket LP #1",
                lpSymbol:              "PRED-LP-1",
                salt:                  keccak256("market-1")
            })
        );
        market  = PredictionMarket(mktAddr);
        lpToken = LPToken(lpAddr);

        vm.stopPrank();

        // ── Fund test actors ─────────────────────────────────────
        _mintAndApprove(alice, 10_000_000e6);
        _mintAndApprove(bob,   10_000_000e6);
        _mintAndApprove(carol, 10_000_000e6);

        // ── Seed initial liquidity from Alice ────────────────────
        vm.startPrank(alice);
        market.addLiquidity(INITIAL_LIQ, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        // ── Delegate governance votes (to self) ──────────────────
        vm.prank(deployer);
        govToken.delegate(deployer);
        // Give alice & bob some tokens for governance tests
        vm.prank(deployer);
        // Transfer from deployer — deployer still holds all 10M tokens
        govToken.transfer(alice, 1_000_000e18);
        govToken.transfer(bob, 500_000e18);
        vm.prank(alice);  govToken.delegate(alice);
        vm.prank(bob);    govToken.delegate(bob);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint USDC to `who` and approve both the market and the factory.
    function _mintAndApprove(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(who);
        usdc.approve(address(factory), type(uint256).max);
    }

    /// @dev Warp past market closeTime and trigger close().
    function _closeMarket() internal {
        vm.warp(block.timestamp + CLOSE_DELAY + 1);
        market.close();
    }

    /// @dev Close → resolve (oracle price already set to PRICE_ABOVE by default).
    function _resolveYes() internal {
        _closeMarket();
        market.resolve();
    }

    /// @dev Close → resolve with NO outcome.
    function _resolveNo() internal {
        aggregator.setAnswer(PRICE_BELOW);
        _closeMarket();
        market.resolve();
    }

    /// @dev Resolve then skip past dispute window and finalize.
    function _finalizeYes() internal {
        _resolveYes();
        vm.warp(block.timestamp + DISPUTE_WIN + 1);
        market.finalize();
    }

    function _finalizeNo() internal {
        _resolveNo();
        vm.warp(block.timestamp + DISPUTE_WIN + 1);
        market.finalize();
    }

    /// @dev Buy YES shares on behalf of `who`; approves market first.
    function _buyYes(address who, uint256 collateral) internal returns (uint256 shares) {
        vm.prank(who);
        shares = market.buyYes(collateral, 0, block.timestamp + 1 hours);
    }

    function _buyNo(address who, uint256 collateral) internal returns (uint256 shares) {
        vm.prank(who);
        shares = market.buyNo(collateral, 0, block.timestamp + 1 hours);
    }

    /// @dev Approve ConditionalTokens on behalf of `who` so claim() can burn.
    function _approveCT(address who) internal {
        vm.prank(who);
        ct.setApprovalForAll(address(market), true);
    }

    /// @dev Execute a timelock action directly in tests (skips governance proposal flow).
    ///      Uses vm.prank(timelock) which is valid in unit tests.
    function _timelockExec(address target, bytes memory data) internal {
        vm.stopPrank();
        vm.startPrank(address(timelock));
        (bool ok, bytes memory ret) = target.call(data);
        vm.stopPrank();
        vm.startPrank(deployer);
        require(ok, string(ret));
    }

    /// @dev Helper to grant a role as if the timelock executed the proposal.
    function _grantTimelockRole(address target, bytes32 role, address account) internal {
        bytes memory data = abi.encodeWithSignature("grantRole(bytes32,address)", role, account);
        _timelockExec(target, data);
    }

    /// @dev Return the YES/NO token IDs for the default market.
    function _ids() internal view returns (uint256 yId, uint256 nId) {
        return ct.getIds(address(market));
    }
}
