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
import "src/interfaces/IdeUSDBalancerRateProvider.sol";
import "src/deUSDBalancerRateProvider.sol";

contract stDeUSDCooldownTest is Test {
    deUSD public deUSDToken;
    stdeUSD public stDeUSD;
    SigUtils public sigUtilsdeUSD;
    SigUtils public sigUtilsstDeUSD;
    deUSDBalancerRateProvider public rateProvider;

    address public owner;
    address public rewarder;
    address public alice;
    address public bob;
    address public greg;

    bytes32 REWARDER_ROLE = keccak256("REWARDER_ROLE");

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event RewardsReceived(uint256 indexed amount);

    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);

    function setUp() public virtual {
        deUSDToken = deUSD(
            address(
                new ERC1967Proxy(address(new deUSD()), abi.encodeWithSignature("initialize(address)", address(this)))
            )
        );

        alice = vm.addr(0xB44DE);
        bob = vm.addr(0x1DE);
        greg = vm.addr(0x6ED);
        owner = vm.addr(0xA11CE);
        rewarder = vm.addr(0x1DEA);
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(greg, "greg");
        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");

        vm.prank(owner);
        stDeUSD = stdeUSD(
            address(
                new ERC1967Proxy(
                    address(new stdeUSD()),
                    abi.encodeWithSignature("initialize(address,address,address)", deUSDToken, rewarder, owner)
                )
            )
        );
        rateProvider = new deUSDBalancerRateProvider(address(stDeUSD));

        sigUtilsdeUSD = new SigUtils(deUSDToken.DOMAIN_SEPARATOR());
        sigUtilsstDeUSD = new SigUtils(stDeUSD.DOMAIN_SEPARATOR());

        deUSDToken.setMinter(address(this));
    }

    function test_constructor() public {
        vm.prank(owner);

        stdeUSD stakingContract = stdeUSD(
            address(
                new ERC1967Proxy(
                    address(new stdeUSD()),
                    abi.encodeWithSignature("initialize(address,address,address)", deUSDToken, rewarder, owner)
                )
            )
        );

        assertEq(stakingContract.owner(), owner);
        assertEq(stakingContract.cooldownDuration(), 90 days);
        assertTrue(address(stakingContract.silo()) != address(0));
    }

    function _mintApproveDeposit(address staker, uint256 amount) internal {
        deUSDToken.mint(staker, amount);

        vm.startPrank(staker);
        deUSDToken.approve(address(stDeUSD), amount);

        uint256 prevRate = rateProvider.getRate();

        vm.expectEmit(true, true, true, false);
        emit Deposit(staker, staker, amount, amount);

        stDeUSD.deposit(amount, staker);
        vm.stopPrank();

        if (prevRate == 0) return;

        uint256 _totalSupply = stDeUSD.totalSupply();

        if (_totalSupply == 0) {
            assertEq(rateProvider.getRate(), 0);
        } else {
            // redeeming can decrease the rate slightly when mint is huge and totalSupply is small
            // decrease < 1e-16 percent
            uint256 newRate = rateProvider.getRate();
            // 1e-16 percent is the max chg https://book.getfoundry.sh/reference/forge-std/assertApproxEqRel
            assertApproxEqRel(newRate, prevRate, 1, "_mint: Rate should not change");
        }
    }

    function _redeem(address staker, uint256 shares, bool expectRevert) internal {
        uint256 balBefore = deUSDToken.balanceOf(staker);

        uint256 prevRate = rateProvider.getRate();

        vm.startPrank(staker);
        stDeUSD.cooldownShares(shares);
        (uint104 cooldownEnd, uint256 deUSDAmount) = stDeUSD.cooldowns(staker);

        uint256 _totalSupply = stDeUSD.totalSupply();
        if (_totalSupply == 0) {
            assertEq(rateProvider.getRate(), 0);
        } else {
            uint256 newRate = rateProvider.getRate();
            assertGe(newRate, prevRate, "_redeem: Rate should not decrease");
            // 1e-16 percent is the max chg https://book.getfoundry.sh/reference/forge-std/assertApproxEqRel
            assertApproxEqRel(newRate, prevRate, 1, "_redeem: Rate should not change");
        }

        vm.warp(cooldownEnd + 1);

        stDeUSD.unstake(staker);
        vm.stopPrank();

        uint256 balAfter = deUSDToken.balanceOf(staker);

        if (expectRevert) {
            assertEq(balBefore, balAfter, "balance should be zero");
        } else {
            assertApproxEqAbs(balBefore + deUSDAmount, balAfter, 1, "bal check");
        }
    }

    function _redeemAssets(address staker, uint256 assets, bool expectRevert) internal {
        uint256 balBefore = deUSDToken.balanceOf(staker);
        uint256 prevRate = rateProvider.getRate();

        vm.startPrank(staker);

        stDeUSD.cooldownAssets(assets);
        (uint104 cooldownEnd, uint256 deUSDAmount) = stDeUSD.cooldowns(staker);

        uint256 _totalSupply = stDeUSD.totalSupply();
        if (_totalSupply == 0) {
            assertEq(rateProvider.getRate(), 0);
        } else {
            uint256 newRate = rateProvider.getRate();
            assertGe(newRate, prevRate, "_redeem: Rate should not decrease");
            // 1e-16 percent is the max chg https://book.getfoundry.sh/reference/forge-std/assertApproxEqRel
            assertApproxEqRel(newRate, prevRate, 1, "_redeem: Rate should not change");
        }

        vm.warp(cooldownEnd + 1);

        stDeUSD.unstake(staker);
        vm.stopPrank();

        uint256 balAfter = deUSDToken.balanceOf(staker);

        if (expectRevert) {
            assertEq(balBefore, balAfter, "balance check revert");
        } else {
            assertEq(balBefore + deUSDAmount, balAfter, "balance check");
        }
    }

    function _transferRewards(uint256 amount, uint256 expectedNewVestingAmount) internal {
        deUSDToken.mint(address(rewarder), amount);
        vm.startPrank(rewarder);

        deUSDToken.approve(address(stDeUSD), amount);
        uint256 prevRate = rateProvider.getRate();

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(rewarder, address(stDeUSD), amount);

        stDeUSD.transferInRewards(amount);

        assertEq(rateProvider.getRate(), prevRate, "Rate should not change");

        assertApproxEqAbs(stDeUSD.getUnvestedAmount(), expectedNewVestingAmount, 1);
        vm.stopPrank();
    }

    function _assertVestedAmountIs(uint256 amount) internal {
        assertApproxEqAbs(stDeUSD.totalAssets(), amount, 2, "vestedAmountIs");
    }

    function testInitialStake() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);

        assertEq(deUSDToken.balanceOf(alice), 0);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), amount);
        assertEq(stDeUSD.balanceOf(alice), amount);
    }

    function testInitialStakeBelowMin() public {
        uint256 amount = 0.99 ether;
        deUSDToken.mint(alice, amount);
        vm.startPrank(alice);
        deUSDToken.approve(address(stDeUSD), amount);
        vm.expectRevert(IstdeUSD.MinSharesViolation.selector);
        stDeUSD.deposit(amount, alice);

        assertEq(deUSDToken.balanceOf(alice), amount);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0);
        assertEq(stDeUSD.balanceOf(alice), 0);
    }

    function testCantCooldownBelowMinShares() public {
        _mintApproveDeposit(alice, 1 ether);

        vm.startPrank(alice);
        deUSDToken.approve(address(stDeUSD), 0.01 ether);
        vm.expectRevert(IstdeUSD.MinSharesViolation.selector);
        stDeUSD.cooldownShares(0.5 ether);
    }

    function testCannotStakeWithoutApproval() public {
        uint256 amount = 100 ether;
        deUSDToken.mint(alice, amount);

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(stDeUSD), 0, amount)
        );
        stDeUSD.deposit(amount, alice);
        vm.stopPrank();

        assertEq(deUSDToken.balanceOf(alice), amount);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0);
        assertEq(stDeUSD.balanceOf(alice), 0);
    }

    function testStakeUnstake() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);

        assertEq(deUSDToken.balanceOf(alice), 0);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), amount);
        assertEq(stDeUSD.balanceOf(alice), amount);

        _redeem(alice, amount, false);

        assertEq(deUSDToken.balanceOf(alice), amount);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0);
        assertEq(stDeUSD.balanceOf(alice), 0);
    }

    function testOnlyRewarderCanReward() public {
        uint256 amount = 100 ether;
        uint256 rewardAmount = 0.5 ether;
        _mintApproveDeposit(alice, amount);

        deUSDToken.mint(bob, rewardAmount);
        vm.startPrank(bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(bob), REWARDER_ROLE
            )
        );
        stDeUSD.transferInRewards(rewardAmount);
        vm.stopPrank();
        assertEq(deUSDToken.balanceOf(alice), 0);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), amount);
        assertEq(stDeUSD.balanceOf(alice), amount);
        _assertVestedAmountIs(amount);
        assertEq(deUSDToken.balanceOf(bob), rewardAmount);
    }

    function testStakingAndUnstakingBeforeAfterReward() public {
        uint256 amount = 100 ether;
        uint256 rewardAmount = 100 ether;
        _mintApproveDeposit(alice, amount);
        _transferRewards(rewardAmount, rewardAmount);
        _redeem(alice, amount, false);
        assertEq(deUSDToken.balanceOf(alice), amount);
        assertEq(stDeUSD.totalSupply(), 0);
    }

    function testFuzzNoJumpInVestedBalance(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1e60);
        _transferRewards(amount, amount);
        vm.warp(block.timestamp + 4 hours);
        _assertVestedAmountIs(amount / 2);
        assertEq(deUSDToken.balanceOf(address(stDeUSD)), amount);
    }

    function testOwnerCannotRescuedeUSD() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);
        bytes4 selector = bytes4(keccak256("InvalidToken()"));
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(selector));
        stDeUSD.rescueTokens(address(deUSDToken), amount, owner);
    }

    function testOwnerCanRescuesdeUSD() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);
        vm.prank(alice);
        stDeUSD.transfer(address(stDeUSD), amount);
        assertEq(stDeUSD.balanceOf(owner), 0);
        vm.startPrank(owner);
        stDeUSD.rescueTokens(address(stDeUSD), amount, owner);
        assertEq(stDeUSD.balanceOf(owner), amount);
    }

    function testOwnerCanChangeRewarder() public {
        assertTrue(stDeUSD.hasRole(REWARDER_ROLE, address(rewarder)));
        address newRewarder = address(0x123);
        vm.startPrank(owner);
        stDeUSD.revokeRole(REWARDER_ROLE, rewarder);
        stDeUSD.grantRole(REWARDER_ROLE, newRewarder);
        assertTrue(!stDeUSD.hasRole(REWARDER_ROLE, address(rewarder)));
        assertTrue(stDeUSD.hasRole(REWARDER_ROLE, newRewarder));
        vm.stopPrank();

        deUSDToken.mint(rewarder, 1 ether);
        deUSDToken.mint(newRewarder, 1 ether);

        vm.startPrank(rewarder);
        deUSDToken.approve(address(stDeUSD), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(rewarder), REWARDER_ROLE
            )
        );
        stDeUSD.transferInRewards(1 ether);
        vm.stopPrank();

        vm.startPrank(newRewarder);
        deUSDToken.approve(address(stDeUSD), 1 ether);
        stDeUSD.transferInRewards(1 ether);
        vm.stopPrank();

        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 1 ether);
        assertEq(deUSDToken.balanceOf(rewarder), 1 ether);
        assertEq(deUSDToken.balanceOf(newRewarder), 0);
    }

    function tesdeUSDValuePersdeUSD() public {
        _mintApproveDeposit(alice, 100 ether);
        _transferRewards(100 ether, 100 ether);
        vm.warp(block.timestamp + 4 hours);
        _assertVestedAmountIs(150 ether);
        assertEq(stDeUSD.convertToAssets(1 ether), 1.5 ether - 1);
        assertEq(stDeUSD.totalSupply(), 100 ether);
        // rounding
        _mintApproveDeposit(bob, 75 ether);
        _assertVestedAmountIs(225 ether);
        assertEq(stDeUSD.balanceOf(alice), 100 ether);
        assertEq(stDeUSD.balanceOf(bob), 50 ether);
        assertEq(stDeUSD.convertToAssets(1 ether), 1.5 ether - 1);

        vm.warp(block.timestamp + 4 hours);

        uint256 vestedAmount = 275 ether;
        _assertVestedAmountIs(vestedAmount);

        assertEq(stDeUSD.convertToAssets(1 ether), (vestedAmount * 1 ether) / 150 ether);

        // rounding
        _redeem(bob, stDeUSD.balanceOf(bob), false);
        _redeem(alice, 100 ether, false);

        assertEq(stDeUSD.balanceOf(alice), 0);
        assertEq(stDeUSD.balanceOf(bob), 0);
        assertEq(stDeUSD.totalSupply(), 0);

        assertApproxEqAbs(deUSDToken.balanceOf(alice), (vestedAmount * 2) / 3, 1);

        // rounding
        assertApproxEqAbs(deUSDToken.balanceOf(bob), vestedAmount / 3, 1);

        assertApproxEqAbs(deUSDToken.balanceOf(address(stDeUSD)), 0, 1);
    }

    function testFairStakeAndUnstakePrices() public {
        uint256 aliceAmount = 100 ether;
        uint256 bobAmount = 1000 ether;
        uint256 rewardAmount = 200 ether;
        _mintApproveDeposit(alice, aliceAmount);
        _transferRewards(rewardAmount, rewardAmount);
        vm.warp(block.timestamp + 4 hours);
        _mintApproveDeposit(bob, bobAmount);
        vm.warp(block.timestamp + 4 hours);
        _redeem(alice, aliceAmount, false);
        _assertVestedAmountIs(bobAmount + (rewardAmount * 5) / 12);
    }

    function testFuzzFairStakeAndUnstakePrices(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 rewardAmount,
        uint256 waitSeconds
    ) public {
        amount1 = bound(amount1, 100 ether, 1e32 - 1);
        amount2 = bound(amount2, 1, 1e32 - 1);
        amount3 = bound(amount3, 1, 1e32 - 1);
        rewardAmount = bound(rewardAmount, 1, 1e32 - 1);
        vm.assume(waitSeconds <= 9 hours);

        uint256 totalContributions = amount1;

        _mintApproveDeposit(alice, amount1);

        _transferRewards(rewardAmount, rewardAmount);

        vm.warp(block.timestamp + waitSeconds);

        uint256 vestedAmount;
        if (waitSeconds > 8 hours) {
            vestedAmount = amount1 + rewardAmount;
        } else {
            vestedAmount = amount1 + rewardAmount - (rewardAmount * (8 hours - waitSeconds)) / 8 hours;
        }

        _assertVestedAmountIs(vestedAmount);

        uint256 bobstDeUSD = (amount2 * (amount1 + 1)) / (vestedAmount + 1);
        if (bobstDeUSD > 0) {
            _mintApproveDeposit(bob, amount2);
            totalContributions += amount2;
        }

        vm.warp(block.timestamp + waitSeconds);

        if (waitSeconds > 4 hours) {
            vestedAmount = totalContributions + rewardAmount;
        } else {
            vestedAmount = totalContributions + rewardAmount - ((4 hours - waitSeconds) * rewardAmount) / 4 hours;
        }

        _assertVestedAmountIs(vestedAmount);

        uint256 gregstDeUSD = (amount3 * (stDeUSD.totalSupply() + 1)) / (vestedAmount + 1);
        if (gregstDeUSD > 0) {
            _mintApproveDeposit(greg, amount3);
            totalContributions += amount3;
        }

        vm.warp(block.timestamp + 8 hours);

        vestedAmount = totalContributions + rewardAmount;

        _assertVestedAmountIs(vestedAmount);

        uint256 deUSDPerstDeUSDBefore = stDeUSD.convertToAssets(1 ether);
        uint256 bobUnstakeAmount = (stDeUSD.balanceOf(bob) * (vestedAmount + 1)) / (stDeUSD.totalSupply() + 1);
        uint256 gregUnstakeAmount = (stDeUSD.balanceOf(greg) * (vestedAmount + 1)) / (stDeUSD.totalSupply() + 1);

        if (bobUnstakeAmount > 0) _redeem(bob, stDeUSD.balanceOf(bob), false);
        uint256 deUSDPerstDeUSDAfter = stDeUSD.convertToAssets(1 ether);
        if (deUSDPerstDeUSDAfter != 0) assertApproxEqAbs(deUSDPerstDeUSDAfter, deUSDPerstDeUSDBefore, 1 ether);

        if (gregUnstakeAmount > 0) _redeem(greg, stDeUSD.balanceOf(greg), false);
        deUSDPerstDeUSDAfter = stDeUSD.convertToAssets(1 ether);
        if (deUSDPerstDeUSDAfter != 0) assertApproxEqAbs(deUSDPerstDeUSDAfter, deUSDPerstDeUSDBefore, 1 ether);

        _redeem(alice, amount1, false);

        assertEq(stDeUSD.totalSupply(), 0);
        assertApproxEqAbs(stDeUSD.totalAssets(), 0, 10 ** 12);
    }

    function testTransferRewardsFailsInsufficientBalance() public {
        deUSDToken.mint(address(rewarder), 99);
        vm.startPrank(rewarder);

        deUSDToken.approve(address(stDeUSD), 100);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(rewarder), 99, 100)
        );
        stDeUSD.transferInRewards(100);
        vm.stopPrank();
    }

    function testTransferRewardsFailsZeroAmount() public {
        deUSDToken.mint(address(rewarder), 100);
        vm.startPrank(rewarder);

        deUSDToken.approve(address(stDeUSD), 100);

        vm.expectRevert(IstdeUSD.InvalidAmount.selector);
        stDeUSD.transferInRewards(0);
        vm.stopPrank();
    }

    function testDecimalsIs18() public {
        assertEq(stDeUSD.decimals(), 18);
    }

    function testMintWithSlippageCheck(uint256 amount) public {
        amount = bound(amount, 1 ether, type(uint256).max / 2);
        deUSDToken.mint(alice, amount * 2);

        assertEq(stDeUSD.balanceOf(alice), 0);

        vm.startPrank(alice);
        deUSDToken.approve(address(stDeUSD), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, amount, amount);
        stDeUSD.mint(amount, alice);

        assertEq(stDeUSD.balanceOf(alice), amount);

        deUSDToken.approve(address(stDeUSD), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, amount, amount);
        stDeUSD.mint(amount, alice);

        assertEq(stDeUSD.balanceOf(alice), amount * 2);
    }

    function testMintToDiffRecipient() public {
        deUSDToken.mint(alice, 1 ether);

        vm.startPrank(alice);

        deUSDToken.approve(address(stDeUSD), 1 ether);

        stDeUSD.deposit(1 ether, bob);

        assertEq(stDeUSD.balanceOf(alice), 0);
        assertEq(stDeUSD.balanceOf(bob), 1 ether);
    }

    function testFuzzCooldownAssetsUnstake(uint256 amount) public {
        amount = bound(amount, 1 ether, 1e40);
        _mintApproveDeposit(alice, amount);

        assertEq(stDeUSD.balanceOf(alice), amount);

        vm.startPrank(alice);

        _redeemAssets(alice, amount, false);

        assertEq(stDeUSD.balanceOf(alice), 0);

        assertEq(deUSDToken.balanceOf(alice), amount);
    }

    function test_fails_v1_exit_functions_cooldownDuration_gt_0() public {
        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.withdraw(0, address(0), address(0));

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.redeem(0, address(0), address(0));

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.withdraw(0, address(0), address(0));

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.redeem(0, address(0), address(0));
    }

    function test_fails_v2_if_set_duration_zero() public {
        vm.prank(owner);
        stDeUSD.setCooldownDuration(0);

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.cooldownAssets(0);

        vm.expectRevert(IstdeUSD.OperationNotAllowed.selector);
        stDeUSD.cooldownShares(0);
    }

    function testFuzzCooldownAssets(uint256 amount) public {
        amount = bound(amount, 1 ether, 1e40);
        _mintApproveDeposit(alice, amount);

        assertEq(stDeUSD.balanceOf(alice), amount);

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, address(stDeUSD.silo()), alice, amount, amount);

        stDeUSD.cooldownAssets(amount);

        assertEq(stDeUSD.balanceOf(alice), 0);
    }

    function testFuzzCooldownShares(uint256 amount) public {
        amount = bound(amount, 1 ether, 1e40);
        _mintApproveDeposit(alice, amount);

        assertEq(stDeUSD.balanceOf(alice), amount);

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, address(stDeUSD.silo()), alice, amount, amount);

        stDeUSD.cooldownShares(amount);

        assertEq(stDeUSD.balanceOf(alice), 0);
    }

    function testSetCooldown_zero() public {
        uint24 previousDuration = stDeUSD.cooldownDuration();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit CooldownDurationUpdated(previousDuration, 0);
        stDeUSD.setCooldownDuration(0);
    }

    function testSetCooldown_error_gt_max() public {
        vm.expectRevert(IstdeUSD.InvalidCooldown.selector);

        vm.prank(owner);
        stDeUSD.setCooldownDuration(90 days + 1);
    }

    function testSetCooldown_fuzz(uint24 newCooldownDuration) public {
        vm.assume(newCooldownDuration > 0 && newCooldownDuration <= 7776000);
        uint24 previousDuration = stDeUSD.cooldownDuration();

        vm.expectEmit(true, true, true, true);
        emit CooldownDurationUpdated(previousDuration, newCooldownDuration);

        vm.prank(owner);
        stDeUSD.setCooldownDuration(newCooldownDuration);
    }
}
