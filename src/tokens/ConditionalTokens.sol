// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";

/// @title ConditionalTokens
/// @notice Single ERC-1155 contract holding outcome shares for every market in the protocol.
/// @dev Token IDs are deterministic: id = uint256(keccak256(abi.encode(market, outcome))).
///      Markets self-authorise mint/burn calls via msg.sender; the factory whitelists them at creation.
contract ConditionalTokens is ERC1155, AccessControl, IConditionalTokens {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    uint8 public constant OUTCOME_YES = 1;
    uint8 public constant OUTCOME_NO = 2;

    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    mapping(address market => bool) public override isAuthorizedMarket;
    mapping(address market => uint256) private _yesId;
    mapping(address market => uint256) private _noId;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address admin) ERC1155("") {
        require(admin != address(0), "Zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedMarket() {
        if (!isAuthorizedMarket[msg.sender]) revert NotAuthorizedMarket();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONDITION PREPARATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Whitelist a market and assign it deterministic YES/NO token IDs.
    /// @dev Only callable by addresses holding FACTORY_ROLE.
    function prepareCondition(address market)
        external
        override
        onlyRole(FACTORY_ROLE)
        returns (uint256 yesId, uint256 noId)
    {
        if (market == address(0)) revert NotAuthorizedMarket();
        if (isAuthorizedMarket[market]) revert ConditionAlreadyPrepared();

        yesId = uint256(keccak256(abi.encode(market, OUTCOME_YES)));
        noId = uint256(keccak256(abi.encode(market, OUTCOME_NO)));

        isAuthorizedMarket[market] = true;
        _yesId[market] = yesId;
        _noId[market] = noId;

        emit ConditionPrepared(market, yesId, noId);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT / BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a complete set (amount YES + amount NO) to `to`.
    /// @dev Must be invoked by an authorised market. The market also collects the 1:1 collateral upstream.
    function mintComplete(address to, uint256 amount) external override onlyAuthorizedMarket {
        address market = msg.sender;
        _mint(to, _yesId[market], amount, "");
        _mint(to, _noId[market], amount, "");
        emit SharesMintedComplete(market, to, amount);
    }

    /// @notice Burn a complete set (amount YES + amount NO) from `from`.
    function burnComplete(address from, uint256 amount) external override onlyAuthorizedMarket {
        address market = msg.sender;
        _burn(from, _yesId[market], amount);
        _burn(from, _noId[market], amount);
        emit SharesBurnedComplete(market, from, amount);
    }

    /// @notice Burn a single outcome's shares (called on claim()).
    function burnSingle(address from, uint8 outcomeIndex, uint256 amount) external override onlyAuthorizedMarket {
        address market = msg.sender;
        uint256 id;
        if (outcomeIndex == OUTCOME_YES) id = _yesId[market];
        else if (outcomeIndex == OUTCOME_NO) id = _noId[market];
        else revert InvalidOutcomeIndex(outcomeIndex);

        _burn(from, id, amount);
        emit SharesBurnedSingle(market, from, outcomeIndex, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    function getIds(address market) external view override returns (uint256, uint256) {
        return (_yesId[market], _noId[market]);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC165 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, IERC165)
        returns (bool)
    {
        return ERC1155.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}
