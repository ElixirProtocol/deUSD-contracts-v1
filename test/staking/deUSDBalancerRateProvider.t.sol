// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {IdeUSDBalancerRateProvider} from "src/interfaces/IdeUSDBalancerRateProvider.sol";
import "src/deUSDBalancerRateProvider.sol";

contract deUSDBalancerRateProviderTest is Test {
    function setUp() public {}

    function test_constructor_checks() public {
        vm.expectRevert(IdeUSDBalancerRateProvider.ZeroAddressException.selector);
        new deUSDBalancerRateProvider(address(0));
    }

    function test_set_deUSD() public {
        deUSDBalancerRateProvider rateProvider = new deUSDBalancerRateProvider(address(this));
        assertEq(address(rateProvider.stDeUSD()), address(this));
    }
}
