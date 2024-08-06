// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IdeUSDSilo} from "src/interfaces/IdeUSDSilo.sol";

/// @title deUSDSilo
contract deUSDSilo is IdeUSDSilo {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Staking vault address
    address public immutable STAKING_VAULT;

    /// @notice deUSD contract
    IERC20 public immutable DEUSD;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows only staking vault
    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param stakingVault Staking vault address
    /// @param _deUSD deUSD contract address
    constructor(address stakingVault, address _deUSD) {
        if (stakingVault == address(0) || _deUSD == address(0)) revert ZeroAddressException();

        STAKING_VAULT = stakingVault;
        DEUSD = IERC20(_deUSD);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws from Silo to address
    /// @param to Address to withdraw to
    /// @param amount Amount to withdraw
    /// @dev only staking vault is allowed to call this
    function withdraw(address to, uint256 amount) external onlyStakingVault {
        DEUSD.transfer(to, amount);
    }
}
