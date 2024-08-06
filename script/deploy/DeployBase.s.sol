// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import {deUSD} from "src/deUSD.sol";
import {deUSDMinting} from "src/deUSDMinting.sol";
import {stdeUSD} from "src/stdeUSD.sol";
import {deUSDLPStaking} from "src/deUSDLPStaking.sol";

import {IWETH9} from "src/interfaces/IWETH9.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address public weth;
    uint256 public maxMintPerBlock;
    uint256 public maxRedeemPerBlock;

    constructor(address _weth, uint256 _maxMintPerBlock, uint256 _maxRedeemPerBlock) {
        weth = _weth;
        maxMintPerBlock = _maxMintPerBlock;
        maxRedeemPerBlock = _maxRedeemPerBlock;
    }

    function setup(address[] memory assets, address[] memory custodians) internal {
        // Start broadcast.
        vm.startBroadcast();

        // Read caller information.
        (, address deployer,) = vm.readCallers();

        // Deploy deUSD
        deUSD deUSDToken = deUSD(
            payable(
                address(
                    new ERC1967Proxy{salt: keccak256(abi.encodePacked("deUSD"))}(
                        address(new deUSD{salt: keccak256(abi.encodePacked("deUSDImplementation"))}()),
                        abi.encodeWithSignature("initialize(address)", deployer)
                    )
                )
            )
        );

        // Deploy deUSDMinting
        deUSDMinting deUSDMintingContract = deUSDMinting(
            payable(
                address(
                    new ERC1967Proxy{salt: keccak256(abi.encodePacked("deUSDMinting"))}(
                        address(new deUSDMinting{salt: keccak256(abi.encodePacked("deUSDMintingImplementation"))}()), ""
                    )
                )
            )
        );

        // Initialize after deploymente so that the creation code of the contract is the same across chains.
        deUSDMintingContract.initialize(
            deUSDToken, IWETH9(weth), assets, custodians, deployer, maxMintPerBlock, maxRedeemPerBlock
        );

        // Deploy stdeUSD
        stdeUSD stdeUSDToken = stdeUSD(
            address(
                new ERC1967Proxy{salt: keccak256(abi.encodePacked("stdeUSD"))}(
                    address(new stdeUSD{salt: keccak256(abi.encodePacked("stdeUSDImplementation"))}()),
                    abi.encodeWithSignature("initialize(address,address,address)", deUSDToken, deployer, deployer)
                )
            )
        );

        // Deploy deUSDLPStaking
        deUSDLPStaking deUSDLPStakingContract = deUSDLPStaking(
            address(
                new ERC1967Proxy{salt: keccak256(abi.encodePacked("deUSDLPStaking"))}(
                    address(new deUSDLPStaking{salt: keccak256(abi.encodePacked("deUSDLPStakingImplementation"))}()),
                    abi.encodeWithSignature("initialize(address)", deployer)
                )
            )
        );

        // Set the deUSD minter
        deUSDToken.setMinter(address(deUSDMintingContract));

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
