// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "test/utils/deUSDMintingUtils.sol";
import "src/interfaces/ISingleAdminAccessControl.sol";
import "openzeppelin/utils/Strings.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

contract deUSDMintingACLTest is deUSDMintingUtils {
    /// @notice Event emitted when a supported asset is added
    event AssetAdded(address indexed asset);

    /// @notice Event emitted when assets are moved to custody provider wallet
    event CustodyTransfer(address indexed wallet, address indexed asset, uint256 amount);

    function setUp() public override {
        super.setUp();
    }

    function test_role_authorization() public {
        vm.deal(trader1, 1 ether);
        vm.deal(maker1, 1 ether);
        vm.deal(maker2, 1 ether);
        vm.startPrank(minter);
        stETHToken.mint(1 * 1e18, maker1);
        stETHToken.mint(1 * 1e18, trader1);
        vm.expectRevert(OnlyMinterErr);
        deUSDToken.mint(address(maker2), 2000 * 1e18);
        vm.expectRevert(OnlyMinterErr);
        deUSDToken.mint(address(trader2), 2000 * 1e18);
    }

    function test_redeem_notRedeemer_revert() public {
        (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) =
            redeem_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.startPrank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(minter), redeemerRole
            )
        );

        deUSDMintingContract.redeem(redeemOrder, takerSignature2);
    }

    function test_fuzz_notMinter_cannot_mint(address nonMinter) public {
        (
            IdeUSDMinting.Order memory mintOrder,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.assume(nonMinter != minter);
        vm.startPrank(nonMinter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(nonMinter), minterRole
            )
        );

        deUSDMintingContract.mint(mintOrder, route, takerSignature);

        assertEq(stETHToken.balanceOf(benefactor), _stETHToDeposit);
        assertEq(deUSDToken.balanceOf(beneficiary), 0);
    }

    function test_fuzz_nonOwner_cannot_add_supportedAsset_revert(address nonOwner) public {
        vm.assume(nonOwner != owner);
        address asset = address(20);
        vm.expectRevert();
        vm.prank(nonOwner);
        deUSDMintingContract.addSupportedAsset(asset);
        assertFalse(deUSDMintingContract.isSupportedAsset(asset));
    }

    function test_fuzz_nonOwner_cannot_remove_supportedAsset_revert(address nonOwner) public {
        vm.assume(nonOwner != owner);
        address asset = address(20);
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        deUSDMintingContract.addSupportedAsset(asset);
        assertTrue(deUSDMintingContract.isSupportedAsset(asset));

        vm.expectRevert();
        vm.prank(nonOwner);
        deUSDMintingContract.removeSupportedAsset(asset);
        assertTrue(deUSDMintingContract.isSupportedAsset(asset));
    }

    function test_collateralManager_canTransfer_custody() public {
        vm.startPrank(owner);
        stETHToken.mint(1000, address(deUSDMintingContract));
        deUSDMintingContract.addCustodianAddress(beneficiary);
        deUSDMintingContract.grantRole(collateralManagerRole, minter);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit CustodyTransfer(beneficiary, address(stETHToken), 1000);
        deUSDMintingContract.transferToCustody(beneficiary, address(stETHToken), 1000);
        assertEq(stETHToken.balanceOf(beneficiary), 1000);
        assertEq(stETHToken.balanceOf(address(deUSDMintingContract)), 0);
    }

    function test_fuzz_nonCollateralManager_cannot_transferCustody_revert(address nonCollateralManager) public {
        vm.assume(
            nonCollateralManager != collateralManager && nonCollateralManager != owner
                && nonCollateralManager != address(0)
        );
        stETHToken.mint(1000, address(deUSDMintingContract));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(nonCollateralManager),
                collateralManagerRole
            )
        );

        vm.prank(nonCollateralManager);
        deUSDMintingContract.transferToCustody(beneficiary, address(stETHToken), 1000);
    }

    /**
     * Gatekeeper tests
     */
    function test_gatekeeper_can_remove_minter() public {
        vm.prank(gatekeeper);

        deUSDMintingContract.removeMinterRole(minter);
        assertFalse(deUSDMintingContract.hasRole(minterRole, minter));
    }

    function test_gatekeeper_can_remove_redeemer() public {
        vm.prank(gatekeeper);

        deUSDMintingContract.removeRedeemerRole(redeemer);
        assertFalse(deUSDMintingContract.hasRole(redeemerRole, redeemer));
    }

    function test_gatekeeper_can_remove_collateral_manager() public {
        vm.prank(gatekeeper);

        deUSDMintingContract.removeCollateralManagerRole(collateralManager);
        assertFalse(deUSDMintingContract.hasRole(collateralManagerRole, collateralManager));
    }

    function test_fuzz_not_gatekeeper_cannot_remove_minter_revert(address notGatekeeper) public {
        vm.assume(notGatekeeper != gatekeeper);
        vm.startPrank(notGatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notGatekeeper), gatekeeperRole
            )
        );

        deUSDMintingContract.removeMinterRole(minter);
        assertTrue(deUSDMintingContract.hasRole(minterRole, minter));
    }

    function test_fuzz_not_gatekeeper_cannot_remove_redeemer_revert(address notGatekeeper) public {
        vm.assume(notGatekeeper != gatekeeper);
        vm.startPrank(notGatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notGatekeeper), gatekeeperRole
            )
        );
        deUSDMintingContract.removeRedeemerRole(redeemer);
        assertTrue(deUSDMintingContract.hasRole(redeemerRole, redeemer));
    }

    function test_fuzz_not_gatekeeper_cannot_remove_collateral_manager_revert(address notGatekeeper) public {
        vm.assume(notGatekeeper != gatekeeper);
        vm.startPrank(notGatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notGatekeeper), gatekeeperRole
            )
        );
        deUSDMintingContract.removeCollateralManagerRole(collateralManager);
        assertTrue(deUSDMintingContract.hasRole(collateralManagerRole, collateralManager));
    }

    function test_gatekeeper_cannot_add_minters_revert() public {
        vm.startPrank(gatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(gatekeeper), adminRole
            )
        );
        deUSDMintingContract.grantRole(minterRole, bob);
        assertFalse(deUSDMintingContract.hasRole(minterRole, bob), "Bob should lack the minter role");
    }

    function test_gatekeeper_cannot_add_collateral_managers_revert() public {
        vm.startPrank(gatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(gatekeeper), adminRole
            )
        );
        deUSDMintingContract.grantRole(collateralManagerRole, bob);
        assertFalse(
            deUSDMintingContract.hasRole(collateralManagerRole, bob), "Bob should lack the collateralManager role"
        );
    }

    function test_gatekeeper_can_disable_mintRedeem() public {
        vm.startPrank(gatekeeper);
        deUSDMintingContract.disableMintRedeem();

        (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(_deUSDToMint, _stETHToDeposit, stETHToken, 1, false);

        vm.prank(minter);
        vm.expectRevert(MaxMintPerBlockExceeded);
        deUSDMintingContract.mint(order, route, takerSignature);

        vm.prank(redeemer);
        vm.expectRevert(MaxRedeemPerBlockExceeded);
        deUSDMintingContract.redeem(order, takerSignature);

        assertEq(deUSDMintingContract.maxMintPerBlock(), 0, "Minting should be disabled");
        assertEq(deUSDMintingContract.maxRedeemPerBlock(), 0, "Redeeming should be disabled");
    }

    // Ensure that the gatekeeper is not allowed to enable/modify the minting
    function test_gatekeeper_cannot_enable_mint_revert() public {
        test_fuzz_nonAdmin_cannot_enable_mint_revert(gatekeeper);
    }

    // Ensure that the gatekeeper is not allowed to enable/modify the redeeming
    function test_gatekeeper_cannot_enable_redeem_revert() public {
        test_fuzz_nonAdmin_cannot_enable_redeem_revert(gatekeeper);
    }

    function test_fuzz_not_gatekeeper_cannot_disable_mintRedeem_revert(address notGatekeeper) public {
        vm.assume(notGatekeeper != gatekeeper);
        vm.startPrank(notGatekeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notGatekeeper), gatekeeperRole
            )
        );
        deUSDMintingContract.disableMintRedeem();

        assertTrue(deUSDMintingContract.maxMintPerBlock() > 0);
        assertTrue(deUSDMintingContract.maxRedeemPerBlock() > 0);
    }

    /**
     * Admin tests
     */
    function test_admin_can_disable_mint(bool performCheckMint) public {
        vm.prank(owner);
        deUSDMintingContract.setMaxMintPerBlock(0);

        if (performCheckMint) maxMint_perBlock_exceeded_revert(1e18);

        assertEq(deUSDMintingContract.maxMintPerBlock(), 0, "The minting should be disabled");
    }

    function test_admin_can_disable_redeem(bool performCheckRedeem) public {
        vm.prank(owner);
        deUSDMintingContract.setMaxRedeemPerBlock(0);

        if (performCheckRedeem) maxRedeem_perBlock_exceeded_revert(1e18);

        assertEq(deUSDMintingContract.maxRedeemPerBlock(), 0, "The redeem should be disabled");
    }

    function test_admin_can_enable_mint() public {
        vm.startPrank(owner);
        deUSDMintingContract.setMaxMintPerBlock(0);

        assertEq(deUSDMintingContract.maxMintPerBlock(), 0, "The minting should be disabled");

        // Re-enable the minting
        deUSDMintingContract.setMaxMintPerBlock(_maxMintPerBlock);

        vm.stopPrank();

        executeMint(stETHToken);

        assertTrue(deUSDMintingContract.maxMintPerBlock() > 0, "The minting should be enabled");
    }

    function test_fuzz_nonAdmin_cannot_enable_mint_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);

        test_admin_can_disable_mint(false);

        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.setMaxMintPerBlock(_maxMintPerBlock);

        maxMint_perBlock_exceeded_revert(1e18);

        assertEq(deUSDMintingContract.maxMintPerBlock(), 0, "The minting should remain disabled");
    }

    function test_fuzz_nonAdmin_cannot_enable_redeem_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);

        test_admin_can_disable_redeem(false);

        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.setMaxRedeemPerBlock(_maxRedeemPerBlock);

        maxRedeem_perBlock_exceeded_revert(1e18);

        assertEq(deUSDMintingContract.maxRedeemPerBlock(), 0, "The redeeming should remain disabled");
    }

    function test_admin_can_enable_redeem() public {
        vm.startPrank(owner);
        deUSDMintingContract.setMaxRedeemPerBlock(0);

        assertEq(deUSDMintingContract.maxRedeemPerBlock(), 0, "The redeem should be disabled");

        // Re-enable the redeeming
        deUSDMintingContract.setMaxRedeemPerBlock(_maxRedeemPerBlock);

        vm.stopPrank();

        executeRedeem(stETHToken);

        assertTrue(deUSDMintingContract.maxRedeemPerBlock() > 0, "The redeeming should be enabled");
    }

    function test_admin_can_add_minter() public {
        vm.startPrank(owner);
        deUSDMintingContract.grantRole(minterRole, bob);

        assertTrue(deUSDMintingContract.hasRole(minterRole, bob), "Bob should have the minter role");
        vm.stopPrank();
    }

    function test_admin_can_remove_minter() public {
        test_admin_can_add_minter();

        vm.startPrank(owner);
        deUSDMintingContract.revokeRole(minterRole, bob);

        assertFalse(deUSDMintingContract.hasRole(minterRole, bob), "Bob should no longer have the minter role");

        vm.stopPrank();
    }

    function test_admin_can_add_gatekeeper() public {
        vm.startPrank(owner);
        deUSDMintingContract.grantRole(gatekeeperRole, bob);

        assertTrue(deUSDMintingContract.hasRole(gatekeeperRole, bob), "Bob should have the gatekeeper role");
        vm.stopPrank();
    }

    function test_admin_can_remove_gatekeeper() public {
        test_admin_can_add_gatekeeper();

        vm.startPrank(owner);
        deUSDMintingContract.revokeRole(gatekeeperRole, bob);

        assertFalse(deUSDMintingContract.hasRole(gatekeeperRole, bob), "Bob should no longer have the gatekeeper role");

        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_remove_minter(address notAdmin) public {
        test_admin_can_add_minter();

        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.revokeRole(minterRole, bob);

        assertTrue(deUSDMintingContract.hasRole(minterRole, bob), "Bob should maintain the minter role");
        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_remove_gatekeeper(address notAdmin) public {
        test_admin_can_add_gatekeeper();

        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.revokeRole(gatekeeperRole, bob);

        assertTrue(deUSDMintingContract.hasRole(gatekeeperRole, bob), "Bob should maintain the gatekeeper role");

        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_add_minter(address notAdmin) public {
        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.grantRole(minterRole, bob);

        assertFalse(deUSDMintingContract.hasRole(minterRole, bob), "Bob should lack the minter role");
        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_add_gatekeeper(address notAdmin) public {
        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(notAdmin), adminRole
            )
        );
        deUSDMintingContract.grantRole(gatekeeperRole, bob);

        assertFalse(deUSDMintingContract.hasRole(gatekeeperRole, bob), "Bob should lack the gatekeeper role");

        vm.stopPrank();
    }

    function test_base_transferAdmin() public {
        vm.prank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        assertTrue(deUSDMintingContract.hasRole(adminRole, owner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, newOwner));

        vm.prank(newOwner);
        deUSDMintingContract.acceptAdmin();
        assertFalse(deUSDMintingContract.hasRole(adminRole, owner));
        assertTrue(deUSDMintingContract.hasRole(adminRole, newOwner));
    }

    function test_transferAdmin_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert();
        deUSDMintingContract.transferAdmin(randomer);
    }

    function test_grantRole_AdminRoleExternally() public {
        vm.startPrank(randomer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(randomer), adminRole
            )
        );
        deUSDMintingContract.grantRole(adminRole, randomer);
        vm.stopPrank();
    }

    function test_revokeRole_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(randomer), adminRole
            )
        );
        deUSDMintingContract.revokeRole(adminRole, owner);
    }

    function test_revokeRole_AdminRole() public {
        vm.startPrank(owner);
        vm.expectRevert();
        deUSDMintingContract.revokeRole(adminRole, owner);
    }

    function test_renounceRole_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert(InvalidAdminChange);
        deUSDMintingContract.renounceRole(adminRole, owner);
    }

    function test_renounceRole_AdminRole() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAdminChange);
        deUSDMintingContract.renounceRole(adminRole, owner);
    }

    function test_revoke_AdminRole() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAdminChange);
        deUSDMintingContract.revokeRole(adminRole, owner);
    }

    function test_grantRole_nonAdminRole() public {
        vm.prank(owner);
        deUSDMintingContract.grantRole(minterRole, randomer);
        assertTrue(deUSDMintingContract.hasRole(minterRole, randomer));
    }

    function test_revokeRole_nonAdminRole() public {
        vm.startPrank(owner);
        deUSDMintingContract.grantRole(minterRole, randomer);
        deUSDMintingContract.revokeRole(minterRole, randomer);
        vm.stopPrank();
        assertFalse(deUSDMintingContract.hasRole(minterRole, randomer));
    }

    function test_renounceRole_nonAdminRole() public {
        vm.prank(owner);
        deUSDMintingContract.grantRole(minterRole, randomer);
        vm.prank(randomer);
        deUSDMintingContract.renounceRole(minterRole, randomer);
        assertFalse(deUSDMintingContract.hasRole(minterRole, randomer));
    }

    function testCanRepeatedlyTransferAdmin() public {
        vm.startPrank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        deUSDMintingContract.transferAdmin(randomer);
        vm.stopPrank();
    }

    function test_renounceRole_forDifferentAccount() public {
        vm.prank(randomer);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlBadConfirmation.selector));
        deUSDMintingContract.renounceRole(minterRole, owner);
    }

    function testCancelTransferAdmin() public {
        vm.startPrank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        deUSDMintingContract.transferAdmin(address(0));
        vm.stopPrank();
        assertTrue(deUSDMintingContract.hasRole(adminRole, owner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, address(0)));
        assertFalse(deUSDMintingContract.hasRole(adminRole, newOwner));
    }

    function test_admin_cannot_transfer_self() public {
        vm.startPrank(owner);
        vm.expectRevert(InvalidAdminChange);
        deUSDMintingContract.transferAdmin(owner);
        vm.stopPrank();
        assertTrue(deUSDMintingContract.hasRole(adminRole, owner));
    }

    function testAdminCanCancelTransfer() public {
        vm.startPrank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        deUSDMintingContract.transferAdmin(address(0));
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert(ISingleAdminAccessControl.NotPendingAdmin.selector);
        deUSDMintingContract.acceptAdmin();

        assertTrue(deUSDMintingContract.hasRole(adminRole, owner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, address(0)));
        assertFalse(deUSDMintingContract.hasRole(adminRole, newOwner));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.startPrank(owner);
        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        deUSDMintingContract.renounceRole(adminRole, owner);

        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        deUSDMintingContract.revokeRole(adminRole, owner);
        vm.stopPrank();
        assertEq(deUSDMintingContract.owner(), owner);
        assertTrue(deUSDMintingContract.hasRole(adminRole, owner));
    }

    function testCanTransferOwnership() public {
        vm.prank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        deUSDMintingContract.acceptAdmin();
        assertTrue(deUSDMintingContract.hasRole(adminRole, newOwner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, owner));
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        vm.startPrank(newOwner);
        deUSDMintingContract.acceptAdmin();
        deUSDMintingContract.grantRole(gatekeeperRole, bob);
        vm.stopPrank();
        assertTrue(deUSDMintingContract.hasRole(adminRole, newOwner));
        assertTrue(deUSDMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testOldOwnerCantPerformOwnerActions() public {
        vm.prank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        deUSDMintingContract.acceptAdmin();
        assertTrue(deUSDMintingContract.hasRole(adminRole, newOwner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, owner));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(owner), adminRole)
        );
        deUSDMintingContract.grantRole(gatekeeperRole, bob);
        assertFalse(deUSDMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testOldOwnerCantTransferOwnership() public {
        vm.prank(owner);
        deUSDMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        deUSDMintingContract.acceptAdmin();
        assertTrue(deUSDMintingContract.hasRole(adminRole, newOwner));
        assertFalse(deUSDMintingContract.hasRole(adminRole, owner));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(owner), adminRole)
        );
        deUSDMintingContract.transferAdmin(bob);
        assertFalse(deUSDMintingContract.hasRole(adminRole, bob));
    }

    function testNonAdminCanRenounceRoles() public {
        vm.prank(owner);
        deUSDMintingContract.grantRole(gatekeeperRole, bob);
        assertTrue(deUSDMintingContract.hasRole(gatekeeperRole, bob));

        vm.prank(bob);
        deUSDMintingContract.renounceRole(gatekeeperRole, bob);
        assertFalse(deUSDMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testCorrectInitConfig() public {
        vm.prank(owner);
        deUSDMinting deUSDMinting2 = deUSDMinting(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new deUSDMinting()),
                        abi.encodeWithSignature(
                            "initialize(address,address,address[],address[],address,uint256,uint256)",
                            deUSDToken,
                            weth,
                            assets,
                            custodians,
                            randomer,
                            _maxMintPerBlock,
                            _maxRedeemPerBlock
                        )
                    )
                )
            )
        );

        assertFalse(deUSDMinting2.hasRole(adminRole, owner));
        assertNotEq(deUSDMinting2.owner(), owner);
        assertTrue(deUSDMinting2.hasRole(adminRole, randomer));
        assertEq(deUSDMinting2.owner(), randomer);
    }
}
