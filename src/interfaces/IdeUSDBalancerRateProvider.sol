// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/// @dev Interface for IdeUSDBalancerRateProvider
interface IdeUSDBalancerRateProvider {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when contract instantiated with no stdeUSD address
    error ZeroAddressException();
}
