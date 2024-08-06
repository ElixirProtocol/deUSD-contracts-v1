// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "test/utils/SigUtils.sol";

import "src/deUSD.sol";
import "src/stdeUSD.sol";
import "src/StakingRewardsDistributor.sol";
import "src/interfaces/IstdeUSD.sol";
import "src/interfaces/IStakingRewardsDistributor.sol";
import "src/interfaces/IdeUSD.sol";
import "test/utils/deUSDMintingUtils.sol";
import "src/interfaces/IdeUSDMinting.sol";
import "openzeppelin/access/Ownable.sol";

contract StakingRewardsDistributorTest is deUSDMintingUtils {
    stdeUSD public stDeUSD;
    StakingRewardsDistributor public stakingRewardsDistributor;

    uint256 public _amount = 100 ether;

    address public operator;
    address public mockRewarder;

    bytes32 OPERATOR_ROLE;
    bytes32 DEFAULT_ADMIN_ROLE;
    bytes32 REWARDER_ROLE;

    uint256 private operatorPrivateKey = uint256(keccak256(abi.encodePacked("operator")));

    // Staking distributor events
    event RewardsReceived(uint256 amount);
    /// @notice Event emitted when tokens are rescued by owner
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    /// @notice This event is fired when the operator changes
    event OperatorUpdated(address indexed newOperator, address indexed previousOperator);
    /// @notice This event is fired when the mint contract changes
    event MintingContractUpdated(address indexed newMintingContract, address indexed previousMintingContract);

    /// @notice Event emitted when a delegated signer is added, enabling it to sign orders on behalf of another address
    event DelegatedSignerAdded(address indexed signer, address indexed delegator);
    /// @notice Event emitted when a delegated signer is removed
    event DelegatedSignerRemoved(address indexed signer, address indexed delegator);
    /// @notice Event emitted when a delegated signer is initiated
    event DelegatedSignerInitiated(address indexed signer, address indexed delegator);

    function setUp() public virtual override {
        super.setUp();

        DEFAULT_ADMIN_ROLE = 0x00;
        REWARDER_ROLE = keccak256("REWARDER_ROLE");

        operator = vm.addr(operatorPrivateKey);
        mockRewarder = makeAddr("mock_rewarder");

        vm.startPrank(owner);

        // The rewarder has to be the stakingRewardsDistributor, so we have a circular dependency
        stDeUSD = stdeUSD(
            address(
                new ERC1967Proxy(
                    address(new stdeUSD()),
                    abi.encodeWithSignature("initialize(address,address,address)", deUSDToken, mockRewarder, owner)
                )
            )
        );

        // Remove the native token entry since it's not an ERC20
        assets.pop();

        stakingRewardsDistributor = new StakingRewardsDistributor(
            deUSDMintingContract, stDeUSD, deUSD(address(deUSDToken)), assets, owner, operator
        );

        // Revoke the mock rewarder needed for the circular dependency
        stDeUSD.revokeRole(REWARDER_ROLE, mockRewarder);

        // Update the rewarder to be the stakingRewardsDistributor
        stDeUSD.grantRole(REWARDER_ROLE, address(stakingRewardsDistributor));

        // Mint stEth to the staking rewards distributor contract
        stETHToken.mint(_stETHToDeposit, address(stakingRewardsDistributor));

        vm.stopPrank();
    }

    function test_check_constructor() public {
        address[] memory assets = new address[](0);

        vm.expectRevert(IStakingRewardsDistributor.InvalidZeroAddress.selector);
        new StakingRewardsDistributor(
            deUSDMinting(payable(address(0))), IstdeUSD(address(0)), deUSD(address(0)), assets, address(0x1), address(0)
        );

        vm.expectRevert(IStakingRewardsDistributor.InvalidZeroAddress.selector);
        new StakingRewardsDistributor(
            deUSDMinting(payable(address(0x1))),
            IstdeUSD(address(0)),
            deUSD(address(0)),
            assets,
            address(0x1),
            address(0)
        );

        vm.expectRevert(IStakingRewardsDistributor.InvalidZeroAddress.selector);
        new StakingRewardsDistributor(
            deUSDMinting(payable(address(0x1))),
            IstdeUSD(address(0x1)),
            deUSD(address(0)),
            assets,
            address(0x1),
            address(0)
        );

        vm.expectRevert(IStakingRewardsDistributor.NoAssetsProvided.selector);
        new StakingRewardsDistributor(
            deUSDMinting(payable(address(0x1))),
            IstdeUSD(address(0x1)),
            deUSD(address(0x1)),
            assets,
            address(0x1),
            address(0)
        );
    }

    // Delegated mint performed by the operator using the available funds from
    // the staking rewards distributor. The deUSD minted is sent to the staking contract
    // calling transferInRewards by the operator, as the staking rewards distributor has the rewarder role
    function test_full_workflow() public {
        test_transfer_rewards_setup();

        // Since the deUSD already landed on the staking rewards contract, send it to the staking contract
        vm.prank(operator);
        vm.expectEmit();
        emit RewardsReceived(_deUSDToMint);
        stakingRewardsDistributor.transferInRewards(_deUSDToMint);

        assertEq(
            deUSDToken.balanceOf(address(stakingRewardsDistributor)),
            0,
            "The staking rewards distributor deUSD balance should be 0"
        );
        assertEq(
            deUSDToken.balanceOf(address(stDeUSD)),
            _deUSDToMint,
            "The staking contract should have the transfered deUSD"
        );
    }

    function test_transfer_rewards_setup() public {
        IdeUSDMinting.Order memory customOrder = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: 1,
            benefactor: address(stakingRewardsDistributor),
            beneficiary: address(stakingRewardsDistributor),
            collateral_asset: address(stETHToken),
            deUSD_amount: _deUSDToMint,
            collateral_amount: _stETHToDeposit
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        IdeUSDMinting.Route memory route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(operator, address(stakingRewardsDistributor))),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        bytes32 digest1 = deUSDMintingContract.hashOrder(customOrder);

        // accept delegation
        vm.prank(operator);
        vm.expectEmit();
        emit DelegatedSignerAdded(operator, address(stakingRewardsDistributor));
        deUSDMintingContract.confirmDelegatedSigner(address(stakingRewardsDistributor));

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(operator, address(stakingRewardsDistributor))),
            uint256(IdeUSDMinting.DelegatedSignerStatus.ACCEPTED),
            "The delegation status should be accepted"
        );

        IdeUSDMinting.Signature memory operatorSig =
            signOrder(operatorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            0,
            "Mismatch in Minting contract stETH balance before mint"
        );
        assertEq(
            stETHToken.balanceOf(address(stakingRewardsDistributor)),
            _stETHToDeposit,
            "Mismatch in benefactor stETH balance before mint"
        );
        assertEq(
            deUSDToken.balanceOf(address(stakingRewardsDistributor)),
            0,
            "Mismatch in beneficiary deUSD balance before mint"
        );

        vm.prank(minter);
        deUSDMintingContract.mint(customOrder, route, operatorSig);

        assertEq(
            stETHToken.balanceOf(address(deUSDMintingContract)),
            _stETHToDeposit,
            "Mismatch in Minting contract stETH balance after mint"
        );
        assertEq(
            stETHToken.balanceOf(address(stakingRewardsDistributor)),
            0,
            "Mismatch in beneficiary stETH balance after mint"
        );
        assertEq(
            deUSDToken.balanceOf(address(stakingRewardsDistributor)),
            _deUSDToMint,
            "Mismatch in beneficiary deUSD balance after mint"
        );
    }

    /**
     * Access control
     */
    function test_set_operator_and_accept_delegation_by_owner() public {
        vm.startPrank(owner);

        vm.expectEmit();
        emit DelegatedSignerInitiated(bob, address(stakingRewardsDistributor));
        emit DelegatedSignerRemoved(operator, address(stakingRewardsDistributor));
        stakingRewardsDistributor.setOperator(bob);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(bob, address(stakingRewardsDistributor))),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        vm.stopPrank();

        assertEq(stakingRewardsDistributor.operator(), bob);

        assertEq(
            uint256(deUSDMintingContract.delegatedSigner(bob, address(stakingRewardsDistributor))),
            uint256(IdeUSDMinting.DelegatedSignerStatus.PENDING),
            "The delegation status should be pending"
        );

        vm.prank(bob);
        vm.expectEmit();
        emit DelegatedSignerAdded(bob, address(stakingRewardsDistributor));
        deUSDMintingContract.confirmDelegatedSigner(address(stakingRewardsDistributor));

        assertEq(stakingRewardsDistributor.operator(), bob);
    }

    function test_non_admin_cannot_set_operator_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.startPrank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));

        stakingRewardsDistributor.setOperator(bob);

        vm.stopPrank();

        assertNotEq(stakingRewardsDistributor.operator(), bob);
    }

    function test_remove_operator() public {
        vm.startPrank(owner);

        stakingRewardsDistributor.setOperator(bob);

        assertEq(stakingRewardsDistributor.operator(), bob);

        stakingRewardsDistributor.setOperator(randomer);

        assertNotEq(stakingRewardsDistributor.operator(), bob);

        vm.stopPrank();
    }

    function test_fuzz_change_operator_role_by_other_reverts(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.startPrank(owner);

        stakingRewardsDistributor.setOperator(bob);

        vm.stopPrank();

        vm.startPrank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));

        stakingRewardsDistributor.setOperator(randomer);

        vm.stopPrank();

        assertEq(stakingRewardsDistributor.operator(), bob);
    }

    function test_revoke_operator_by_myself_reverts() public {
        vm.startPrank(owner);

        stakingRewardsDistributor.setOperator(bob);

        vm.stopPrank();

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(bob)));

        stakingRewardsDistributor.setOperator(randomer);

        vm.stopPrank();

        assertEq(stakingRewardsDistributor.operator(), bob);
    }

    function test_admin_cannot_renounce() public {
        vm.prank(owner);

        vm.expectRevert(IStakingRewardsDistributor.CantRenounceOwnership.selector);
        stakingRewardsDistributor.renounceOwnership();

        assertEq(stakingRewardsDistributor.owner(), owner);
    }

    function test_non_admin_cannot_give_admin_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.startPrank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        stakingRewardsDistributor.transferOwnership(bob);

        vm.stopPrank();

        assertEq(stakingRewardsDistributor.owner(), owner);
    }

    function test_operator_cannot_transfer_rewards_insufficient_funds_revert() public {
        vm.prank(operator);

        vm.expectRevert(IStakingRewardsDistributor.InsufficientFunds.selector);
        stakingRewardsDistributor.transferInRewards(1);

        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0, "The staking contract should hold no funds");
    }

    function test_non_operator_cannot_transfer_rewards(address notOperator) public {
        vm.assume(notOperator != operator);

        test_transfer_rewards_setup();

        vm.prank(notOperator);

        vm.expectRevert(IStakingRewardsDistributor.OnlyOperator.selector);
        stakingRewardsDistributor.transferInRewards(_deUSDToMint);

        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0, "The staking contract should hold no funds");
    }

    function test_operator_cannot_transfer_more_rewards_than_available() public {
        test_transfer_rewards_setup();

        vm.prank(operator);

        vm.expectRevert(IStakingRewardsDistributor.InsufficientFunds.selector);
        stakingRewardsDistributor.transferInRewards(_deUSDToMint + 1);

        assertEq(deUSDToken.balanceOf(address(stDeUSD)), 0, "The staking contract should hold no funds");
    }

    function test_fuzz_non_owner_cannot_approve_tokens_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.prank(notAdmin);

        address[] memory asset = new address[](1);
        asset[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));

        stakingRewardsDistributor.approveToMintContract(asset);
    }

    function test_owner_can_approve_tokens() public {
        address testToken = address(new MockToken("Test", "T", 18, owner));
        address testToken2 = address(new MockToken("Test2", "T2", 18, owner));
        address[] memory asset = new address[](2);
        asset[0] = testToken;
        asset[1] = testToken2;

        vm.prank(owner);
        stakingRewardsDistributor.approveToMintContract(asset);
    }

    // Only when using test forks
    //function test_owner_can_approve_token_usdt() public {
    //  vm.prank(owner);
    //
    //  address[] memory asset = new address[](1);
    //  asset[0] = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    //
    //  stakingRewardsDistributor.approveToMintContract(asset);
    //}

    function test_assert_correct_owner() public {
        vm.prank(owner);

        assertEq(stakingRewardsDistributor.owner(), owner);
    }

    function test_owner_set_minting_contract() public {
        vm.prank(owner);

        address payable mockAddress = payable(address(1));

        vm.expectEmit();
        emit MintingContractUpdated(mockAddress, address(deUSDMintingContract));
        stakingRewardsDistributor.setMintingContract(deUSDMinting(mockAddress));

        assertEq(address(stakingRewardsDistributor.mintContract()), mockAddress);
    }

    function test_fuzz_non_owner_cannot_set_minting_contract(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.prank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        stakingRewardsDistributor.setMintingContract(deUSDMinting(payable(address(1))));

        assertEq(address(stakingRewardsDistributor.mintContract()), address(deUSDMintingContract));
    }

    function test_fuzz_non_owner_cannot_rescue_tokens(address notAdmin) public {
        vm.assume(notAdmin != owner);

        vm.prank(notAdmin);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));

        stakingRewardsDistributor.rescueTokens(address(deUSDToken), randomer, _deUSDToMint);

        assertTrue(deUSDToken.balanceOf(notAdmin) != _deUSDToMint);
    }

    function test_owner_can_rescue_tokens() public {
        test_transfer_rewards_setup();

        vm.prank(owner);

        vm.expectEmit();
        emit TokensRescued(address(deUSDToken), randomer, _deUSDToMint);
        stakingRewardsDistributor.rescueTokens(address(deUSDToken), randomer, _deUSDToMint);

        assertEq(deUSDToken.balanceOf(randomer), _deUSDToMint);
    }

    function test_owner_can_rescue_ETH() public {
        address ethPlaceholder = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        vm.deal(address(stakingRewardsDistributor), 1e18);
        vm.prank(owner);

        vm.expectEmit();
        emit TokensRescued(ethPlaceholder, randomer, 1e18);
        stakingRewardsDistributor.rescueTokens(ethPlaceholder, randomer, 1e18);

        assertEq(randomer.balance, 1e18);
    }

    function test_correct_initial_config() public {
        assertEq(stakingRewardsDistributor.owner(), owner);
        assertEq(address(stakingRewardsDistributor.mintContract()), address(deUSDMintingContract));
        assertEq(address(stakingRewardsDistributor.DEUSD_TOKEN()), address(deUSDToken));
    }

    function test_revoke_erc20_approvals() public {
        vm.startPrank(owner);

        address oldMintContract = address(stakingRewardsDistributor.mintContract());

        // Change the current minting contract address
        stakingRewardsDistributor.setMintingContract(deUSDMinting(payable(address(1))));

        stakingRewardsDistributor.revokeApprovals(assets, oldMintContract);

        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(IERC20(assets[i]).allowance(address(stakingRewardsDistributor), oldMintContract), 0);
        }

        vm.stopPrank();
    }

    function test_cannot_revoke_erc20_approvals_from_current_mint_contract_revert() public {
        vm.startPrank(owner);

        address currentMintContract = address(stakingRewardsDistributor.mintContract());

        vm.expectRevert(IStakingRewardsDistributor.InvalidAddressCurrentMintContract.selector);
        stakingRewardsDistributor.revokeApprovals(assets, currentMintContract);

        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(
                IERC20(assets[i]).allowance(address(stakingRewardsDistributor), currentMintContract), type(uint256).max
            );
        }

        vm.stopPrank();
    }

    function test_non_admin_cannot_revoke_erc20_approvals_revert(address notAdmin) public {
        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);

        address currentMintContract = address(stakingRewardsDistributor.mintContract());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        stakingRewardsDistributor.revokeApprovals(assets, currentMintContract);

        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(
                IERC20(assets[i]).allowance(address(stakingRewardsDistributor), currentMintContract), type(uint256).max
            );
        }

        vm.stopPrank();
    }
}
