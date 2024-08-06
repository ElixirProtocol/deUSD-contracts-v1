// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/* solhint-disable private-vars-leading-underscore  */

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {Vm} from "forge-std/Vm.sol";

import "src/deUSD.sol";
import "test/utils/deUSDMintingUtils.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";

contract deUSDTest is Test, deUSDMintingUtils {
    deUSD internal _deUSDToken;

    uint256 internal _ownerPrivateKey;
    uint256 internal _newOwnerPrivateKey;
    uint256 internal _minterPrivateKey;
    uint256 internal _newMinterPrivateKey;

    address internal _owner;
    address internal _newOwner;
    address internal _minter;
    address internal _newMinter;

    function setUp() public virtual override {
        _ownerPrivateKey = 0xA11CE;
        _newOwnerPrivateKey = 0xA14CE;
        _minterPrivateKey = 0xB44DE;
        _newMinterPrivateKey = 0xB45DE;

        _owner = vm.addr(_ownerPrivateKey);
        _newOwner = vm.addr(_newOwnerPrivateKey);
        _minter = vm.addr(_minterPrivateKey);
        _newMinter = vm.addr(_newMinterPrivateKey);

        vm.label(_minter, "minter");
        vm.label(_owner, "owner");
        vm.label(_newMinter, "_newMinter");
        vm.label(_newOwner, "newOwner");

        _deUSDToken = deUSD(
            address(new ERC1967Proxy(address(new deUSD()), abi.encodeWithSignature("initialize(address)", _owner)))
        );

        vm.prank(_owner);
        _deUSDToken.setMinter(_minter);
    }

    function testCorrectInitialConfig() public {
        assertEq(_deUSDToken.owner(), _owner);
        assertEq(_deUSDToken.minter(), _minter);
    }

    function testCantInitWithNoOwner() public {
        deUSD deUSDImplementation = new deUSD();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        deUSDToken = deUSD(
            address(
                new ERC1967Proxy(
                    address(deUSDImplementation), abi.encodeWithSignature("initialize(address)", address(0))
                )
            )
        );
    }

    function testOwnershipCannotBeRenounced() public {
        vm.prank(_owner);
        vm.expectRevert(CantRenounceOwnershipErr);
        _deUSDToken.renounceOwnership();
        assertEq(_deUSDToken.owner(), _owner);
        assertNotEq(_deUSDToken.owner(), address(0));
    }

    function testCanTransferOwnership() public {
        vm.prank(_owner);
        _deUSDToken.transferOwnership(_newOwner);
        vm.prank(_newOwner);
        _deUSDToken.acceptOwnership();
        assertEq(_deUSDToken.owner(), _newOwner);
        assertNotEq(_deUSDToken.owner(), _owner);
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(_owner);
        _deUSDToken.transferOwnership(_newOwner);
        vm.startPrank(_newOwner);
        _deUSDToken.acceptOwnership();
        _deUSDToken.setMinter(_newMinter);
        assertEq(_deUSDToken.minter(), _newMinter);
        assertNotEq(_deUSDToken.minter(), _minter);
    }

    function testOnlyOwnerCanSetMinter() public {
        vm.prank(_newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _newOwner));
        _deUSDToken.setMinter(_newMinter);
        assertEq(_deUSDToken.minter(), _minter);
    }

    function testOwnerCantMint() public {
        vm.prank(_owner);
        vm.expectRevert(OnlyMinterErr);
        _deUSDToken.mint(_newMinter, 100);
    }

    function testMinterCanMint() public {
        assertEq(_deUSDToken.balanceOf(_newMinter), 0);
        vm.prank(_minter);
        _deUSDToken.mint(_newMinter, 100);
        assertEq(_deUSDToken.balanceOf(_newMinter), 100);
    }

    function testMinterCantMintToZeroAddress() public {
        vm.prank(_minter);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        _deUSDToken.mint(address(0), 100);
    }

    function testNewMinterCanMint() public {
        assertEq(_deUSDToken.balanceOf(_newMinter), 0);
        vm.prank(_owner);
        _deUSDToken.setMinter(_newMinter);
        vm.prank(_newMinter);
        _deUSDToken.mint(_newMinter, 100);
        assertEq(_deUSDToken.balanceOf(_newMinter), 100);
    }

    function testOldMinterCantMint() public {
        assertEq(_deUSDToken.balanceOf(_newMinter), 0);
        vm.prank(_owner);
        _deUSDToken.setMinter(_newMinter);
        vm.prank(_minter);
        vm.expectRevert(OnlyMinterErr);
        _deUSDToken.mint(_newMinter, 100);
        assertEq(_deUSDToken.balanceOf(_newMinter), 0);
    }

    function testOldOwnerCantTransferOwnership() public {
        vm.prank(_owner);
        _deUSDToken.transferOwnership(_newOwner);
        vm.prank(_newOwner);
        _deUSDToken.acceptOwnership();
        assertNotEq(_deUSDToken.owner(), _owner);
        assertEq(_deUSDToken.owner(), _newOwner);
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _owner));
        _deUSDToken.transferOwnership(_newMinter);
        assertEq(_deUSDToken.owner(), _newOwner);
    }

    function testOldOwnerCantSetMinter() public {
        vm.prank(_owner);
        _deUSDToken.transferOwnership(_newOwner);
        vm.prank(_newOwner);
        _deUSDToken.acceptOwnership();
        assertNotEq(_deUSDToken.owner(), _owner);
        assertEq(_deUSDToken.owner(), _newOwner);
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _owner));
        _deUSDToken.setMinter(_newMinter);
        assertEq(_deUSDToken.minter(), _minter);
    }
}
