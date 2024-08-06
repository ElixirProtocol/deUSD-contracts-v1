// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import "src/deUSD.sol";
import "src/stdeUSD.sol";
import "src/interfaces/IstdeUSD.sol";
import "src/interfaces/IdeUSD.sol";
import "src/interfaces/ISingleAdminAccessControl.sol";

contract stdeUSDACL is Test {
    deUSD public deusdToken;
    stdeUSD public stakedDeUSD;
    SigUtils public sigUtilsdeUSD;
    SigUtils public sigUtilsstdeUSD;

    address public owner;
    address public rewarder;
    address public alice;
    address public newOwner;
    address public greg;

    bytes32 public DEFAULT_ADMIN_ROLE;
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event RewardsReceived(uint256 indexed amount);

    function setUp() public virtual {
        deusdToken = deUSD(
            address(
                new ERC1967Proxy(address(new deUSD()), abi.encodeWithSignature("initialize(address)", address(this)))
            )
        );

        alice = vm.addr(0xB44DE);
        newOwner = vm.addr(0x1DE);
        greg = vm.addr(0x6ED);
        owner = vm.addr(0xA11CE);
        rewarder = vm.addr(0x1DEA);
        vm.label(alice, "alice");
        vm.label(newOwner, "newOwner");
        vm.label(greg, "greg");
        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");

        vm.prank(owner);
        stakedDeUSD = stdeUSD(
            address(
                new ERC1967Proxy(
                    address(new stdeUSD()),
                    abi.encodeWithSignature("initialize(address,address,address)", deusdToken, rewarder, owner)
                )
            )
        );

        DEFAULT_ADMIN_ROLE = stakedDeUSD.DEFAULT_ADMIN_ROLE();

        sigUtilsdeUSD = new SigUtils(deusdToken.DOMAIN_SEPARATOR());
        sigUtilsstdeUSD = new SigUtils(stakedDeUSD.DOMAIN_SEPARATOR());
    }

    function testCorrectSetup() public {
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testCancelTransferAdmin() public {
        vm.startPrank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        stakedDeUSD.transferAdmin(address(0));
        vm.stopPrank();
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function testAdminCannotTransferSelf() public {
        vm.startPrank(owner);
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        stakedDeUSD.transferAdmin(owner);
        vm.stopPrank();
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testAdminCanCancelTransfer() public {
        vm.startPrank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        stakedDeUSD.transferAdmin(address(0));
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert(ISingleAdminAccessControl.NotPendingAdmin.selector);
        stakedDeUSD.acceptAdmin();

        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.startPrank(owner);
        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stakedDeUSD.renounceRole(DEFAULT_ADMIN_ROLE, owner);

        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        stakedDeUSD.revokeRole(DEFAULT_ADMIN_ROLE, owner);
        vm.stopPrank();
        assertEq(stakedDeUSD.owner(), owner);
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testCanTransferOwnership() public {
        vm.prank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedDeUSD.acceptAdmin();
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        vm.startPrank(newOwner);
        stakedDeUSD.acceptAdmin();
        stakedDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, newOwner);
        stakedDeUSD.addToBlacklist(alice, true);
        vm.stopPrank();
        assertTrue(stakedDeUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice));
    }

    function testOldOwnerCantPerformOwnerActions() public {
        vm.prank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedDeUSD.acceptAdmin();
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(owner), DEFAULT_ADMIN_ROLE
            )
        );
        stakedDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertFalse(stakedDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
    }

    function testOldOwnerCantTransferOwnership() public {
        vm.prank(owner);
        stakedDeUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedDeUSD.acceptAdmin();
        assertTrue(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(owner), DEFAULT_ADMIN_ROLE
            )
        );
        stakedDeUSD.transferAdmin(alice);
        assertFalse(stakedDeUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));
    }

    function testNonAdminCantRenounceRoles() public {
        vm.prank(owner);
        stakedDeUSD.grantRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stakedDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stakedDeUSD.renounceRole(BLACKLIST_MANAGER_ROLE, alice);
        assertTrue(stakedDeUSD.hasRole(BLACKLIST_MANAGER_ROLE, alice));
    }
}
