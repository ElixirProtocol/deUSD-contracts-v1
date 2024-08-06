// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "test/utils/deUSDMintingUtils.sol";

contract deUSDMintingTest is deUSDMintingUtils {
    /// @notice Event emitted when a supported asset is added
    event AssetAdded(address indexed asset);

    /// @notice Event emitted when a supported asset is removed
    event AssetRemoved(address indexed asset);

    function setUp() public override {
        super.setUp();
    }

    function test_mint() public {
        executeMint(stETHToken);
    }

    function test_redeem() public {
        executeRedeem(stETHToken);
        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), 0, "Mismatch in stETH balance");
        assertEq(stETHToken.balanceOf(beneficiary), _stETHToDeposit, "Mismatch in stETH balance");
        assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in deUSD balance");
    }

    function test_redeem_invalidNonce_revert() public {
        // Unset the max redeem per block limit
        vm.prank(owner);
        deUSDMintingContract.setMaxRedeemPerBlock(type(uint256).max);

        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.startPrank(redeemer);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);

        vm.expectRevert(InvalidNonce);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);
    }

    function test_nativeEth_withdraw() public {
        vm.deal(address(deUSDMintingContract), _stETHToDeposit);

        IdeUSDMinting.Order memory order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 8,
            benefactor: benefactor,
            beneficiary: benefactor,
            collateral_asset: address(stETHToken),
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _deUSDToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        // taker
        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        assertEq(deUSDToken.balanceOf(benefactor), 0);

        vm.recordLogs();
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
        vm.getRecordedLogs();

        assertEq(deUSDToken.balanceOf(benefactor), _deUSDToMint);

        //redeem
        IdeUSDMinting.Order memory redeemOrder = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.REDEEM,
            expiry: block.timestamp + 10 minutes,
            nonce: 800,
            benefactor: benefactor,
            beneficiary: benefactor,
            collateral_asset: NATIVE_TOKEN,
            deUSD_amount: _deUSDToMint,
            collateral_amount: _stETHToDeposit
        });

        // taker
        vm.startPrank(benefactor);
        deUSDToken.approve(address(deUSDMintingContract), _deUSDToMint);

        bytes32 digest3 = deUSDMintingContract.hashOrder(redeemOrder);
        IdeUSDMinting.Signature memory takerSignature2 =
            signOrder(benefactorPrivateKey, digest3, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        vm.startPrank(redeemer);
        deUSDMintingContract.redeem(redeemOrder, takerSignature2);

        assertEq(stETHToken.balanceOf(benefactor), 0);
        assertEq(deUSDToken.balanceOf(benefactor), 0);
        assertEq(benefactor.balance, _stETHToDeposit);

        vm.stopPrank();
    }

    function test_fuzz_mint_noSlippage(uint256 expectedAmount) public {
        vm.assume(expectedAmount > 0 && expectedAmount < _maxMintPerBlock);

        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(expectedAmount, _stETHToDeposit, stETHToken, 1, false);

        vm.recordLogs();
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
        vm.getRecordedLogs();
        assertEq(stETHToken.balanceOf(benefactor), 0);
        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), _stETHToDeposit);
        assertEq(deUSDToken.balanceOf(beneficiary), expectedAmount);
    }

    function test_multipleValid_custodyRatios_addresses() public {
        uint256 _smalldeUSDToMint = 1.75 * 10 ** 23;
        IdeUSDMinting.Order memory order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 14,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(stETHToken),
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _smalldeUSDToMint
        });

        address[] memory targets = new address[](3);
        targets[0] = address(deUSDMintingContract);
        targets[1] = custodian1;
        targets[2] = custodian2;

        uint256[] memory ratios = new uint256[](3);
        ratios[0] = 3_000;
        ratios[1] = 4_000;
        ratios[2] = 3_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        // taker
        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);

        vm.prank(minter);
        vm.expectRevert(InvalidRoute);
        deUSDMintingContract.mint(order, route, takerSignature);

        vm.prank(owner);
        deUSDMintingContract.addCustodianAddress(custodian2);

        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);

        assertEq(stETHToken.balanceOf(benefactor), 0);
        assertEq(deUSDToken.balanceOf(beneficiary), _smalldeUSDToMint);

        assertEq(stETHToken.balanceOf(address(custodian1)), (_stETHToDeposit * 4) / 10);
        assertEq(stETHToken.balanceOf(address(custodian2)), (_stETHToDeposit * 3) / 10);
        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), (_stETHToDeposit * 3) / 10);

        // remove custodian and expect reversion
        vm.prank(owner);
        deUSDMintingContract.removeCustodianAddress(custodian2);

        vm.prank(minter);
        vm.expectRevert(InvalidRoute);
        deUSDMintingContract.mint(order, route, takerSignature);
    }

    function test_fuzz_multipleInvalid_custodyRatios_revert(uint256 ratio1) public {
        ratio1 = bound(ratio1, 0, UINT256_MAX - 7_000);
        vm.assume(ratio1 != 3_000);

        IdeUSDMinting.Order memory mintOrder = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 15,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(stETHToken),
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _deUSDToMint
        });

        address[] memory targets = new address[](2);
        targets[0] = address(deUSDMintingContract);
        targets[1] = owner;

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = ratio1;
        ratios[1] = 7_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(mintOrder);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);

        vm.expectRevert(InvalidRoute);
        vm.prank(minter);
        deUSDMintingContract.mint(mintOrder, route, takerSignature);

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);
        assertEq(deUSDToken.balanceOf(beneficiary), 0);

        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), 0);
        assertEq(stETHToken.balanceOf(owner), 0);
    }

    function test_fuzz_singleInvalid_custodyRatio_revert(uint256 ratio1) public {
        vm.assume(ratio1 != 10_000);

        IdeUSDMinting.Order memory order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 16,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(stETHToken),
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _deUSDToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = ratio1;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        // taker
        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);

        vm.expectRevert(InvalidRoute);
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);
        assertEq(deUSDToken.balanceOf(beneficiary), 0);

        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), 0);
    }

    function test_unsupported_assets_ERC20_revert() public {
        vm.startPrank(owner);
        deUSDMintingContract.removeSupportedAsset(address(stETHToken));
        stETHToken.mint(_stETHToDeposit, benefactor);
        vm.stopPrank();

        IdeUSDMinting.Order memory order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 18,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(stETHToken),
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _deUSDToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        // taker
        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert(UnsupportedAsset);
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
        vm.getRecordedLogs();
    }

    function test_unsupported_assets_ETH_revert() public {
        vm.startPrank(owner);
        vm.deal(benefactor, _stETHToDeposit);
        vm.stopPrank();

        IdeUSDMinting.Order memory order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 19,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: NATIVE_TOKEN,
            collateral_amount: _stETHToDeposit,
            deUSD_amount: _deUSDToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        // taker
        vm.startPrank(benefactor);
        stETHToken.approve(address(deUSDMintingContract), _stETHToDeposit);

        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        IdeUSDMinting.Signature memory takerSignature =
            signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert(UnsupportedAsset);
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
        vm.getRecordedLogs();
    }

    function test_expired_orders_revert() public {
        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.warp(block.timestamp + 11 minutes);

        vm.recordLogs();
        vm.expectRevert(SignatureExpired);
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
        vm.getRecordedLogs();
    }

    function test_add_and_remove_supported_asset() public {
        address asset = address(20);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        vm.startPrank(owner);
        deUSDMintingContract.addSupportedAsset(asset);
        assertTrue(deUSDMintingContract.isSupportedAsset(asset));

        vm.expectEmit(true, false, false, false);
        emit AssetRemoved(asset);
        deUSDMintingContract.removeSupportedAsset(asset);
        assertFalse(deUSDMintingContract.isSupportedAsset(asset));
    }

    function test_cannot_add_asset_already_supported_revert() public {
        address asset = address(20);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        vm.startPrank(owner);
        deUSDMintingContract.addSupportedAsset(asset);
        assertTrue(deUSDMintingContract.isSupportedAsset(asset));

        vm.expectRevert(InvalidAssetAddress);
        deUSDMintingContract.addSupportedAsset(asset);
    }

    function test_cannot_removeAsset_not_supported_revert() public {
        address asset = address(20);
        assertFalse(deUSDMintingContract.isSupportedAsset(asset));

        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        deUSDMintingContract.removeSupportedAsset(asset);
    }

    function test_cannotAdd_addressZero_revert() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        deUSDMintingContract.addSupportedAsset(address(0));
    }

    function test_cannotAdd_deUSD_revert() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        deUSDMintingContract.addSupportedAsset(address(deUSDToken));
    }

    function test_sending_redeem_order_to_mint_revert() public {
        (IdeUSDMinting.Order memory order, IdeUSDMinting.Signature memory takerSignature) =
            redeem_setup(1 ether, 50 ether, stETHToken, 20, false);

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        vm.expectRevert(InvalidOrder);
        vm.prank(minter);
        deUSDMintingContract.mint(order, route, takerSignature);
    }

    function test_sending_mint_order_to_redeem_revert() public {
        (IdeUSDMinting.Order memory order, IdeUSDMinting.Signature memory takerSignature,) =
            mint_setup(1 ether, 50 ether, stETHToken, 20, false);

        vm.expectRevert(InvalidOrder);
        vm.prank(redeemer);
        deUSDMintingContract.redeem(order, takerSignature);
    }

    function test_receive_eth() public {
        assertEq(address(deUSDMintingContract).balance, 0);
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        (bool success,) = address(deUSDMintingContract).call{value: 10_000 ether}("");
        assertTrue(success);
        assertEq(address(deUSDMintingContract).balance, 10_000 ether);
    }
}
