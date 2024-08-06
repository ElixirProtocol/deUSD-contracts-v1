// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "test/utils/deUSDMintingUtils.sol";
import "src/interfaces/IdeUSDMinting.sol";

contract deUSDMintingDelegateTest is deUSDMintingUtils {
    /// @notice Event emitted when a delegated signer is added, enabling it to sign orders on behalf of another address
    event DelegatedSignerAdded(address indexed signer, address indexed delegator);

    /// @notice Event emitted when a delegated signer is removed
    event DelegatedSignerRemoved(address indexed signer, address indexed delegator);

    /// @notice Event emitted when a delegated signer is initiated
    event DelegatedSignerInitiated(address indexed signer, address indexed delegator);

    function setUp() public override {
        super.setUp();
    }

    function testDelegateSuccessfulMint() public {
        (deUSDMinting.Order memory order,, deUSDMinting.Route memory route) =
            mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        // request delegation
        vm.prank(benefactor);
        vm.expectEmit();
        emit DelegatedSignerInitiated(trader2, benefactor);
        deUSDMintingContract.setDelegatedSigner(trader2);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, benefactor)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);

        // accept delegation
        vm.prank(trader2);
        vm.expectEmit();
        emit DelegatedSignerAdded(trader2, benefactor);
        deUSDMintingContract.confirmDelegatedSigner(benefactor);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, benefactor)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.ACCEPTED),
            "The delegation status should be accepted"
        );

        IdeUSDMinting.Signature memory trader2Sig =
            signOrder(trader2PrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in benefactor stETH balance before mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance before mint");

        vm.prank(minter);
        deUSDMintingContract.mint(order, route, trader2Sig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            _stETHToDeposit,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(stETHToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary stETH balance after mint");
        assertEq(deUSDToken.balanceOf(beneficiary), _deUSDToMint, "Mismatch in beneficiary deUSD balance after mint");
    }

    function testDelegateFailureMint() public {
        (deUSDMinting.Order memory order,, deUSDMinting.Route memory route) =
            mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        vm.prank(trader2);
        IdeUSDMinting.Signature memory trader2Sig =
            signOrder(trader2PrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in benefactor stETH balance before mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance before mint");

        // assert that the delegation is rejected
        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(minter, trader2)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.REJECTED),
            "The delegation status should be rejected"
        );

        vm.prank(minter);
        vm.expectRevert(InvalidSignature);
        deUSDMintingContract.mint(order, route, trader2Sig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in beneficiary stETH balance after mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance after mint");
    }

    function testDelegateSuccessfulRedeem() public {
        (deUSDMinting.Order memory order,) = redeem_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        // request delegation
        vm.prank(beneficiary);
        vm.expectEmit();
        emit DelegatedSignerInitiated(trader2, beneficiary);
        deUSDMintingContract.setDelegatedSigner(trader2);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, beneficiary)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);

        // accept delegation
        vm.prank(trader2);
        vm.expectEmit();
        emit DelegatedSignerAdded(trader2, beneficiary);
        deUSDMintingContract.confirmDelegatedSigner(beneficiary);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, beneficiary)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.ACCEPTED),
            "The delegation status should be accepted"
        );

        IdeUSDMinting.Signature memory trader2Sig =
            signOrder(trader2PrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            _stETHToDeposit,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(stETHToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary stETH balance before mint");
        assertEq(deUSDToken.balanceOf(beneficiary), _deUSDToMint, "Mismatch in beneficiary deUSD balance before mint");

        vm.prank(redeemer);
        deUSDMintingContract.redeem(order, trader2Sig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(stETHToken.balanceOf(beneficiary), _stETHToDeposit, "Mismatch in beneficiary stETH balance after mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance after mint");
    }

    function testDelegateFailureRedeem() public {
        (deUSDMinting.Order memory order,) = redeem_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        vm.prank(trader2);
        IdeUSDMinting.Signature memory trader2Sig =
            signOrder(trader2PrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            _stETHToDeposit,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(stETHToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary stETH balance before mint");
        assertEq(deUSDToken.balanceOf(beneficiary), _deUSDToMint, "Mismatch in beneficiary deUSD balance before mint");

        // assert that the delegation is rejected
        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(redeemer, trader2)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.REJECTED),
            "The delegation status should be rejected"
        );

        vm.prank(redeemer);
        vm.expectRevert(InvalidSignature);
        deUSDMintingContract.redeem(order, trader2Sig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            _stETHToDeposit,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(stETHToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary stETH balance after mint");
        assertEq(deUSDToken.balanceOf(beneficiary), _deUSDToMint, "Mismatch in beneficiary deUSD balance after mint");
    }

    function testCanUndelegate() public {
        (deUSDMinting.Order memory order,, deUSDMinting.Route memory route) =
            mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        // delegate request
        vm.prank(benefactor);
        vm.expectEmit();
        emit DelegatedSignerInitiated(trader2, benefactor);
        deUSDMintingContract.setDelegatedSigner(trader2);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, benefactor)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        // accept the delegation
        vm.prank(trader2);
        vm.expectEmit();
        emit DelegatedSignerAdded(trader2, benefactor);
        deUSDMintingContract.confirmDelegatedSigner(benefactor);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, benefactor)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.ACCEPTED),
            "The delegation status should be accepted"
        );

        // remove the delegation
        vm.prank(benefactor);
        vm.expectEmit();
        emit DelegatedSignerRemoved(trader2, benefactor);
        deUSDMintingContract.removeDelegatedSigner(trader2);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(trader2, benefactor)),
            uint256(IdeUSDMinting.DelegatedSignerStatus.REJECTED),
            "The delegation status should be accepted"
        );

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        vm.prank(trader2);
        IdeUSDMinting.Signature memory trader2Sig =
            signOrder(trader2PrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in benefactor stETH balance before mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance before mint");

        vm.prank(minter);
        vm.expectRevert(InvalidSignature);
        deUSDMintingContract.mint(order, route, trader2Sig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit, "Mismatch in beneficiary stETH balance after mint");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in beneficiary deUSD balance after mint");
    }
}
