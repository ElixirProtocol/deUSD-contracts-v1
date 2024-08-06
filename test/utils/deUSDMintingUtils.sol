// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "test/utils/MintingBaseSetup.sol";
import "forge-std/console.sol";

// These functions are reused across multiple files
contract deUSDMintingUtils is MintingBaseSetup {
    function maxMint_perBlock_exceeded_revert(uint256 excessiveMintAmount) public {
        // This amount is always greater than the allowed max mint per block
        vm.assume(excessiveMintAmount > deUSDMintingContract.maxMintPerBlock());
        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(excessiveMintAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.prank(minter);
        vm.expectRevert(MaxMintPerBlockExceeded);
        deUSDMintingContract.mint(order, route, takerSignature);

        assertEq(deUSDToken.balanceOf(beneficiary), 0, "The beneficiary balance should be 0");
        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), 0, "The elixir minting stETH balance should be 0");
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in stETH balance");
    }

    function maxRedeem_perBlock_exceeded_revert(uint256 excessiveRedeemAmount) public {
        // Set the max mint per block to the same value as the max redeem in order to get to the redeem
        vm.prank(owner);
        deUSDMintingContract.setMaxMintPerBlock(excessiveRedeemAmount);

        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(excessiveRedeemAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.startPrank(redeemer);
        vm.expectRevert(MaxRedeemPerBlockExceeded);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);

        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), _stETHToDeposit, "Mismatch in stETH balance");
        assertEq(stETHToken.balanceOf(beneficiary), 0, "Mismatch in stETH balance");
        assertEq(deUSDToken.balanceOf(beneficiary), excessiveRedeemAmount, "Mismatch in deUSD balance");

        vm.stopPrank();
    }

    function executeMint(IERC20 collateralAsset) public {
        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(_deUSDToMint, _stETHToDeposit, collateralAsset, 1, false);

        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
    }

    function executeRedeem(IERC20 collateralAsset) public {
        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(_deUSDToMint, _stETHToDeposit, collateralAsset, 1, false);
        vm.prank(redeemer);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);
    }
}
