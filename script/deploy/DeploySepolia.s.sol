// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {DeployBase} from "script/deploy/DeployBase.s.sol";

contract DeploySepolia is DeployBase {
    constructor() DeployBase(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9, type(uint256).max, type(uint256).max) {}

    function run() external {
        address[] memory assets = new address[](1);
        assets[0] = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

        address[] memory custodians = new address[](1);
        custodians[0] = 0x85F45B3Ab65132b38b71e19fF9cF33106217a644;

        setup(assets, custodians);
    }

    // Exclude from coverage report
    function test() public override {}
}
