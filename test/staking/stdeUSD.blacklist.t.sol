// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "test/utils/SigUtils.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import {deUSD} from "src/deUSD.sol";
import {stdeUSD} from "src/stdeUSD.sol";
import "src/interfaces/IstdeUSD.sol";
import "src/interfaces/IdeUSD.sol";
import "src/interfaces/ISingleAdminAccessControl.sol";

contract stdeUSDBlacklistTest is Test {
    deUSD public deUSDToken;
    stdeUSD public stDeUSD;
    SigUtils public sigUtilsdeUSD;
    SigUtils public sigUtilsstdeUSD;
    uint256 public _amount = 100 ether;

    address public owner;
    address public alice;
    address public bob;
    address public greg;
    address public rewarder;

    bytes32 SOFT_RESTRICTED_STAKER_ROLE;
    bytes32 FULL_RESTRICTED_STAKER_ROLE;
    bytes32 DEFAULT_ADMIN_ROLE;
    bytes32 BLACKLIST_MANAGER_ROLE;
    bytes32 REWARDER_ROLE;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amountToDistribute);
    event RewardsReceived(uint256 indexed amount);

    function setUp() public virtual {
        deUSDToken = deUSD(
            address(
                new ERC1967Proxy(address(new deUSD()), abi.encodeWithSignature("initialize(address)", address(this)))
            )
        );

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        greg = makeAddr("greg");
        owner = makeAddr("owner");
        rewarder = makeAddr("rewarder");

        deUSDToken.setMinter(address(this));

        vm.startPrank(owner);
        stDeUSD = stdeUSD(
            address(
                new ERC1967Proxy(
                    address(new stdeUSD()),
                    abi.encodeWithSignature("initialize(address,address,address)", deUSDToken, rewarder, owner)
                )
            )
        );
        vm.stopPrank();

        FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");
        SOFT_RESTRICTED_STAKER_ROLE = keccak256("SOFT_RESTRICTED_STAKER_ROLE");
        DEFAULT_ADMIN_ROLE = 0x00;
        BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
        REWARDER_ROLE = keccak256("REWARDER_ROLE");
    }

    function _mintApproveDeposit(address staker, uint256 amount, bool expectRevert) internal {
        deUSDToken.mint(staker, amount);

        vm.startPrank(staker);
        deUSDToken.approve(address(stDeUSD), amount);

        uint256 sharesBefore = stDeUSD.balanceOf(staker);
        if (expectRevert) {
            vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit Deposit(staker, staker, amount, amount);
        }
        stDeUSD.deposit(amount, staker);
        uint256 sharesAfter = stDeUSD.balanceOf(staker);
        if (expectRevert) {
            assertEq(sharesAfter, sharesBefore);
        } else {
            assertApproxEqAbs(sharesAfter - sharesBefore, amount, 1);
        }
        vm.stopPrank();
    }

    function _redeem(address staker, uint256 amount, bool expectRevert) internal {
        uint256 balBefore = deUSDToken.balanceOf(staker);

        vm.startPrank(staker);

        if (expectRevert) {
            vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        } else {}

        stDeUSD.cooldownAssets(amount);
        (uint104 cooldownEnd, uint256 assetsOut) = stDeUSD.cooldowns(staker);

        vm.warp(cooldownEnd + 1);

        stDeUSD.unstake(staker);
        vm.stopPrank();

        uint256 balAfter = deUSDToken.balanceOf(staker);

        if (expectRevert) {
            assertEq(balBefore, balAfter);
        } else {
            assertApproxEqAbs(assetsOut, balAfter - balBefore, 1);
        }
    }

    function _transferRewards(uint256 amount, uint256 expectedNewVestingAmount) internal {
        deUSDToken.mint(address(rewarder), amount);
        vm.startPrank(rewarder);

        deUSDToken.approve(address(stDeUSD), amount);

        vm.expectEmit(true, false, false, true);
        emit IERC20.Transfer(rewarder, address(stDeUSD), amount);

        stDeUSD.transferInRewards(amount);

        assertApproxEqAbs(stDeUSD.getUnvestedAmount(), expectedNewVestingAmount, 1);
        vm.stopPrank();
    }

    function testStakeFlowCommonUser() public {
        _mintApproveDeposit(greg, _amount, false);

        assertEq(deUSDToken.balanceOf(greg), 0);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), _amount);
        assertEq(stDeUSD.balanceOf(greg), _amount);

        _redeem(greg, _amount, false);

        assertEq(deUSDToken.balanceOf(greg), _amount);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0);
        assertEq(stDeUSD.balanceOf(greg), 0);
    }

    /**
     * Soft blacklist: mints not allowed. Burns or transfers are allowed
     */
    function test_softBlacklist_deposit_reverts() public {
        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _mintApproveDeposit(alice, _amount, true);
    }

    function test_softBlacklist_withdraw_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _redeem(alice, _amount, false);
    }

    function test_softBlacklist_transfer_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.prank(alice);
        stDeUSD.transfer(bob, _amount);
    }

    function test_softBlacklist_transferFrom_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.prank(alice);
        stDeUSD.approve(bob, _amount);

        vm.prank(bob);
        stDeUSD.transferFrom(alice, bob, _amount);
    }

    /**
     * Full blacklist: mints, burns or transfers are not allowed
     */
    function test_fullBlacklist_deposit_reverts() public {
        // Alice full blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _mintApproveDeposit(alice, _amount, true);
    }

    function test_fullBlacklist_withdraw_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _redeem(alice, _amount, true);
    }

    function test_fullBlacklist_transfer_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        vm.prank(alice);
        stDeUSD.transfer(bob, _amount);
    }

    function test_fullBlacklist_transferFrom_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.prank(alice);
        stDeUSD.approve(bob, _amount);

        vm.prank(bob);

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.transferFrom(alice, bob, _amount);
    }

    function test_fullBlacklist_can_not_be_transfer_recipient() public {
        _mintApproveDeposit(alice, _amount, false);
        _mintApproveDeposit(bob, _amount, false);

        // Alice full blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        vm.prank(bob);
        stDeUSD.transfer(alice, _amount);
    }

    function test_fullBlacklist_user_can_not_burn_and_donate_to_vault() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice full blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InvalidReceiver.selector, address(0x0000000000000000000000000000000000000000)
            )
        );
        vm.prank(alice);
        stDeUSD.transfer(address(0), _amount);
    }

    /**
     * Soft and Full blacklist: mints, burns or transfers are not allowed
     */
    function test_softFullBlacklist_deposit_reverts() public {
        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _mintApproveDeposit(alice, _amount, true);

        // Alice full blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();
        _mintApproveDeposit(alice, _amount, true);
    }

    function test_softFullBlacklist_withdraw_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _redeem(alice, _amount / 3, false);

        // Alice full blacklisted
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        _redeem(alice, _amount / 3, true);
    }

    function test_softFullBlacklist_transfer_pass() public {
        _mintApproveDeposit(alice, _amount, false);

        // Alice soft blacklisted can transfer
        vm.startPrank(owner);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.prank(alice);
        stDeUSD.transfer(bob, _amount / 3);

        // Alice full blacklisted cannot transfer
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.stopPrank();

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        vm.prank(alice);
        stDeUSD.transfer(bob, _amount / 3);
    }

    /**
     * redistributeLockedAmount
     */
    function test_redistributeLockedAmount() public {
        _mintApproveDeposit(alice, _amount, false);
        uint256 aliceStakedBalance = stDeUSD.balanceOf(alice);
        uint256 previousTotalSupply = stDeUSD.totalSupply();
        assertEq(aliceStakedBalance, _amount);

        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);

        vm.expectEmit(true, true, true, true);
        emit LockedAmountRedistributed(alice, bob, _amount);

        stDeUSD.redistributeLockedAmount(alice, bob);

        vm.stopPrank();

        assertEq(stDeUSD.balanceOf(alice), 0);
        assertEq(stDeUSD.balanceOf(bob), _amount);
        assertEq(stDeUSD.totalSupply(), previousTotalSupply);
    }

    function testCanBurnOnRedistribute() public {
        _mintApproveDeposit(alice, _amount, false);
        _mintApproveDeposit(bob, _amount, false);
        uint256 aliceStakedBalance = stDeUSD.balanceOf(alice);
        uint256 previousTotalSupply = stDeUSD.totalSupply();
        uint256 previodeUSDUSDBalance = deUSDToken.balanceOf(address(stDeUSD));
        uint256 previodeUSDUSDPerSdeUSD = stDeUSD.totalAssets() / stDeUSD.totalSupply();
        assertEq(aliceStakedBalance, _amount);

        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);

        stDeUSD.redistributeLockedAmount(alice, address(0));

        vm.stopPrank();

        assertEq(stDeUSD.balanceOf(alice), 0);
        assertEq(stDeUSD.totalSupply(), previousTotalSupply - _amount);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), previodeUSDUSDBalance);
        assertEq(stDeUSD.totalAssets() / stDeUSD.totalSupply(), previodeUSDUSDPerSdeUSD);
        assertTrue(deUSDToken.balanceOf(address(stDeUSD)) > stDeUSD.totalAssets());
        vm.warp(block.timestamp + 8 hours);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), stDeUSD.totalAssets());
    }

    function testCantBurnOnRedistributeWhileVesting() public {
        _mintApproveDeposit(alice, _amount, false);
        _mintApproveDeposit(bob, _amount, false);
        _transferRewards(_amount, _amount);
        vm.startPrank(owner);
        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.expectRevert(IstdeUSD.StillVesting.selector);
        stDeUSD.redistributeLockedAmount(alice, address(0));
        vm.stopPrank();
        assertEq(stDeUSD.balanceOf(alice), _amount);
    }

    /**
     * Access control
     */
    function test_renounce_reverts() public {
        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        vm.expectRevert();
        stDeUSD.renounceRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.expectRevert();
        stDeUSD.renounceRole(SOFT_RESTRICTED_STAKER_ROLE, alice);
    }

    function test_grant_role() public {
        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        assertEq(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice), true);
        assertEq(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, alice), true);
    }

    function test_revoke_role() public {
        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        assertEq(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice), true);
        assertEq(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, alice), true);

        stDeUSD.revokeRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.revokeRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        assertEq(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice), false);
        assertEq(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, alice), false);

        vm.stopPrank();
    }

    function test_revoke_role_by_other_reverts() public {
        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        vm.startPrank(bob);

        vm.expectRevert();
        stDeUSD.revokeRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.expectRevert();
        stDeUSD.revokeRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        assertEq(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice), true);
        assertEq(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, alice), true);
    }

    function test_revoke_role_by_myself_reverts() public {
        vm.startPrank(owner);

        stDeUSD.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        stDeUSD.grantRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        vm.startPrank(alice);

        vm.expectRevert();
        stDeUSD.revokeRole(FULL_RESTRICTED_STAKER_ROLE, alice);
        vm.expectRevert();
        stDeUSD.revokeRole(SOFT_RESTRICTED_STAKER_ROLE, alice);

        vm.stopPrank();

        assertEq(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice), true);
        assertEq(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, alice), true);
    }

    function testAdminCannotRenounce() public {
        vm.startPrank(owner);

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.renounceRole(DEFAULT_ADMIN_ROLE, owner);

        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        stDeUSD.revokeRole(DEFAULT_ADMIN_ROLE, owner);

        vm.stopPrank();

        assertTrue(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertEq(stDeUSD.owner(), owner);
    }

    function testBlacklistManagerCanBlacklist() public {
        vm.prank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        vm.startPrank(alice);
        stDeUSD.addToBlacklist(bob, true);
        assertTrue(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, bob));

        stDeUSD.addToBlacklist(bob, false);
        assertTrue(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, bob));
        vm.stopPrank();
    }

    function testBlacklistManagerCannotRedistribute() public {
        vm.prank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        _mintApproveDeposit(bob, 1000 ether, false);
        assertEq(stDeUSD.balanceOf(bob), 1000 ether);

        vm.startPrank(alice);
        stDeUSD.addToBlacklist(bob, true);
        assertTrue(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, bob));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(alice), DEFAULT_ADMIN_ROLE
            )
        );
        stDeUSD.redistributeLockedAmount(bob, alice);
        assertEq(stDeUSD.balanceOf(bob), 1000 ether);
        vm.stopPrank();
    }

    function testBlackListManagerCannotAddOthers() public {
        vm.prank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(alice), DEFAULT_ADMIN_ROLE
            )
        );
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, bob);
    }

    function testBlacklistManagerCanUnblacklist() public {
        vm.prank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        vm.startPrank(alice);
        stDeUSD.addToBlacklist(bob, true);
        assertTrue(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, bob));

        stDeUSD.addToBlacklist(bob, false);
        assertTrue(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, bob));

        stDeUSD.removeFromBlacklist(bob, true);
        assertFalse(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, bob));

        stDeUSD.removeFromBlacklist(bob, false);
        assertFalse(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, bob));
        vm.stopPrank();
    }

    function testBlacklistManagerCanNotBlacklistAdmin() public {
        vm.prank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        vm.startPrank(alice);
        vm.expectRevert(IstdeUSD.CantBlacklistOwner.selector);
        stDeUSD.addToBlacklist(owner, true);
        vm.expectRevert(IstdeUSD.CantBlacklistOwner.selector);
        stDeUSD.addToBlacklist(owner, false);
        vm.stopPrank();

        assertFalse(stDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, owner));
        assertFalse(stDeUSD.hasRole(SOFT_RESTRICTED_STAKER_ROLE, owner));
    }

    function testOwnerCanRemoveBlacklistManager() public {
        vm.startPrank(owner);
        stDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
        assertFalse(stDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));

        stDeUSD.revokeRole(BLACKLIST_MANAGER_ROLE, alice);
        vm.stopPrank();

        assertFalse(stDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
    }
}
