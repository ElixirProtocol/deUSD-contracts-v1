// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {stdeUSD} from "src/stdeUSD.sol";
import {IdeUSDBalancerRateProvider} from "src/interfaces/IdeUSDBalancerRateProvider.sol";

/// @title deUSDBalancerRateProvider
/// @notice Exposes a getRate function to enable stdeUSD use in the Balancer protocol
contract deUSDBalancerRateProvider is IdeUSDBalancerRateProvider {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice stdeUSD contract that this rate provider is for
    stdeUSD public immutable stDeUSD;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _stdeUSDAddress The address of the stdeUSD contract
    constructor(address _stdeUSDAddress) {
        if (_stdeUSDAddress == address(0)) revert ZeroAddressException();
        stDeUSD = stdeUSD(_stdeUSDAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deUSD per stdeUSD
    function getRate() external view returns (uint256) {
        stDeUSD.convertToAssets(1e18);
    }
}
