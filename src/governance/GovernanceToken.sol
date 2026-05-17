// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GovernanceToken
/// @author Prediction Market team
/// @notice ERC20 with on-chain voting power and gasless approvals.
/// @dev    ERC20Votes uses checkpointed delegated voting weight; ERC20Permit allows EIP-2612 signatures.
///         The token is timestamp-clocked rather than block-clocked, which is the recommended mode on L2
///         where block numbers do not advance monotonically with time (Arbitrum compresses blocks).
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxSupplyExceeded(uint256 attempted, uint256 cap);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param admin     The DAO timelock — receives DEFAULT_ADMIN_ROLE.
    /// @param initialReceiver The initial supply recipient (treasury / multisig at bootstrap).
    /// @param initialSupply   Bootstrap supply minted at deployment.
    constructor(address admin, address initialReceiver, uint256 initialSupply)
        ERC20("Prediction DAO Token", "PRED")
        ERC20Permit("Prediction DAO Token")
    {
        require(admin != address(0) && initialReceiver != address(0), "Zero address");
        require(initialSupply <= MAX_SUPPLY, "Initial supply exceeds cap");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);

        if (initialSupply > 0) {
            _mint(initialReceiver, initialSupply);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                MINTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint new tokens — gated by MINTER_ROLE, which is initially only the Timelock.
    /// @dev    Hard supply cap is enforced at the contract level.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          CLOCK OVERRIDES (EIP-6372)
    //////////////////////////////////////////////////////////////*/

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /*//////////////////////////////////////////////////////////////
                         REQUIRED SOLIDITY OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
