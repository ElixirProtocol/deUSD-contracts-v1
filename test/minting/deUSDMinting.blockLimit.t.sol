// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/* solhint-disable func-name-mixedcase  */

import "test/utils/deUSDMintingUtils.sol";

contract deUSDMintingBlockLimitTest is deUSDMintingUtils {
    /// @notice Event emitted when the max mint per block is changed
    event MaxMintPerBlockChanged(uint256 indexed oldMaxMintPerBlock, uint256 indexed newMaxMintPerBlock);

    /// @notice Event emitted when the max redeem per block is changed
    event MaxRedeemPerBlockChanged(uint256 indexed oldMaxRedeemPerBlock, uint256 indexed newMaxRedeemPerBlock);

    /**
     * Max mint per block tests
     */

    // Ensures that the minted per block amount raises accordingly
    // when multiple mints are performed
    function test_multiple_mints() public {
        uint256 maxMintAmount = deUSDMintingContract.maxMintPerBlock();
        uint256 firstMintAmount = maxMintAmount / 4;
        uint256 secondMintAmount = maxMintAmount / 2;
        (
            IdeUSDMinting.Order memory aOrder,
            IdeUSDMinting.Signature memory aTakerSignature,
            IdeUSDMinting.Route memory aRoute
        ) = mint_setup(firstMintAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.prank(minter);
        deUSDMintingContract.mint(aOrder, aRoute, aTakerSignature);

        vm.prank(owner);
        stETHToken.mint(_stETHToDeposit, benefactor);

        (
            IdeUSDMinting.Order memory bOrder,
            IdeUSDMinting.Signature memory bTakerSignature,
            IdeUSDMinting.Route memory bRoute
        ) = mint_setup(secondMintAmount, _stETHToDeposit, stETHToken, 2, true);
        vm.prank(minter);
        deUSDMintingContract.mint(bOrder, bRoute, bTakerSignature);

        assertEq(
            deUSDMintingContract.mintedPerBlock(block.number),
            firstMintAmount + secondMintAmount,
            "Incorrect minted amount"
        );
        assertTrue(
            deUSDMintingContract.mintedPerBlock(block.number) < maxMintAmount, "Mint amount exceeded without revert"
        );
    }

    function test_fuzz_maxMint_perBlock_exceeded_revert(uint256 excessiveMintAmount) public {
        // This amount is always greater than the allowed max mint per block
        vm.assume(excessiveMintAmount > deUSDMintingContract.maxMintPerBlock());

        maxMint_perBlock_exceeded_revert(excessiveMintAmount);
    }

    function test_fuzz_mint_maxMint_perBlock_exceeded_revert(uint256 excessiveMintAmount) public {
        vm.assume(excessiveMintAmount > deUSDMintingContract.maxMintPerBlock());
        (
            IdeUSDMinting.Order memory mintOrder,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(excessiveMintAmount, _stETHToDeposit, stETHToken, 1, false);

        // maker
        vm.startPrank(minter);
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);
        assertEq(deUSDToken.balanceOf(beneficiary), 0);

        vm.expectRevert(MaxMintPerBlockExceeded);
        // minter passes in permit signature data
        deUSDMintingContract.mint(mintOrder, route, takerSignature);

        assertEq(
            stETHToken.balanceOf(benefactor),
            _stETHToDeposit,
            "The benefactor stEth balance should be the same as the minted stEth"
        );
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "The beneficiary deUSD balance should be 0");
    }

    function test_fuzz_nextBlock_mint_is_zero(uint256 mintAmount) public {
        vm.assume(mintAmount < deUSDMintingContract.maxMintPerBlock() && mintAmount > 0);
        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);

        vm.roll(block.number + 1);

        assertEq(
            deUSDMintingContract.mintedPerBlock(block.number),
            0,
            "The minted amount should reset to 0 in the next block"
        );
    }

    function test_fuzz_maxMint_perBlock_setter(uint256 newMaxMintPerBlock) public {
        vm.assume(newMaxMintPerBlock > 0);

        uint256 oldMaxMintPerBlock = deUSDMintingContract.maxMintPerBlock();

        vm.prank(owner);
        vm.expectEmit();
        emit MaxMintPerBlockChanged(oldMaxMintPerBlock, newMaxMintPerBlock);

        deUSDMintingContract.setMaxMintPerBlock(newMaxMintPerBlock);

        assertEq(deUSDMintingContract.maxMintPerBlock(), newMaxMintPerBlock, "The max mint per block setter failed");
    }

    /**
     * Max redeem per block tests
     */

    // Ensures that the redeemed per block amount raises accordingly
    // when multiple mints are performed
    function test_multiple_redeem() public {
        uint256 maxRedeemAmount = deUSDMintingContract.maxRedeemPerBlock();
        uint256 firstRedeemAmount = maxRedeemAmount / 4;
        uint256 secondRedeemAmount = maxRedeemAmount / 2;

        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(firstRedeemAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.prank(redeemer);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);

        vm.prank(owner);
        stETHToken.mint(_stETHToDeposit, benefactor);

        (IdeUSDMinting.Order memory bRedeemOrder, IdeUSDMinting.Signature memory bTakerSignature2) =
            redeem_setup(secondRedeemAmount, _stETHToDeposit, stETHToken, 2, true);

        vm.prank(redeemer);
        deUSDMintingContract.redeem(bRedeemOrder, bTakerSignature2);

        assertEq(
            deUSDMintingContract.mintedPerBlock(block.number),
            firstRedeemAmount + secondRedeemAmount,
            "Incorrect minted amount"
        );
        assertTrue(
            deUSDMintingContract.redeemedPerBlock(block.number) < maxRedeemAmount,
            "Redeem amount exceeded without revert"
        );
    }

    function test_fuzz_maxRedeem_perBlock_exceeded_revert(uint256 excessiveRedeemAmount) public {
        // This amount is always greater than the allowed max redeem per block
        vm.assume(excessiveRedeemAmount > deUSDMintingContract.maxRedeemPerBlock());

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

    function test_fuzz_nextBlock_redeem_is_zero(uint256 redeemAmount) public {
        vm.assume(redeemAmount < deUSDMintingContract.maxRedeemPerBlock() && redeemAmount > 0);
        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(redeemAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.startPrank(redeemer);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);

        vm.roll(block.number + 1);

        assertEq(
            deUSDMintingContract.redeemedPerBlock(block.number),
            0,
            "The redeemed amount should reset to 0 in the next block"
        );
        vm.stopPrank();
    }

    function test_fuzz_maxRedeem_perBlock_setter(uint256 newMaxRedeemPerBlock) public {
        vm.assume(newMaxRedeemPerBlock > 0);

        uint256 oldMaxRedeemPerBlock = deUSDMintingContract.maxMintPerBlock();

        vm.prank(owner);
        vm.expectEmit();
        emit MaxRedeemPerBlockChanged(oldMaxRedeemPerBlock, newMaxRedeemPerBlock);
        deUSDMintingContract.setMaxRedeemPerBlock(newMaxRedeemPerBlock);

        assertEq(
            deUSDMintingContract.maxRedeemPerBlock(), newMaxRedeemPerBlock, "The max redeem per block setter failed"
        );
    }
}
