// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {ERC20PermitUpgradeable} from "openzeppelin-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20BurnableUpgradeable} from "openzeppelin-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IdeUSD} from "src/interfaces/IdeUSD.sol";

/// @title deUSD
contract deUSD is
    IdeUSD,
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Minter address
    address public minter;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Prevent the implementation contract from being initialized.
    /// @dev The proxy contract state will still be able to call this function because the constructor does not affect the proxy state.
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    /// @param _owner The owner of the contract
    function initialize(address _owner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __ERC20_init("Elixir's deUSD", "deUSD");
        __ERC20Permit_init("deUSD");
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets minter address
    /// @param newMinter new minter address
    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert ZeroAddressException();

        minter = newMinter;
        emit MinterUpdated(newMinter, minter);
    }

    /// @notice Mints deUSD
    /// @param to The address to mint to
    /// @param amount The amount to mint
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Disallows renouncing ownership of contract
    function renounceOwnership() public view override onlyOwner {
        revert CantRenounceOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
