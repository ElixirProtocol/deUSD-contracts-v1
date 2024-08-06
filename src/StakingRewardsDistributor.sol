// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "openzeppelin/access/Ownable2Step.sol";
import {deUSDMinting} from "src/deUSDMinting.sol";

import {IStakingRewardsDistributor} from "src/interfaces/IStakingRewardsDistributor.sol";
import {IstdeUSD} from "src/interfaces/IstdeUSD.sol";
import {deUSD} from "src/deUSD.sol";

/// @title StakingRewardsDistributor
/// @notice This helper contract allow us to distribute the staking rewards without the need of multisig transactions. It increases
/// the distribution frequency and automates almost the whole process, we also mitigate some arbitrage opportunities with this approach.
/// @dev We have two roles:
/// - The owner of this helper will be the multisig, only used for configuration calls.
/// - The operator will be the delegated signer and is only allowed to mint deUSD using the available funds that land
///   in this contract and calling transferInRewards to send the minted deUSD rewards to the staking contract. The operator
///   can be replaced by the owner at any time with a single transaction.
contract StakingRewardsDistributor is Ownable2Step, IStakingRewardsDistributor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice placeholder address for ETH
    address internal constant _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Elixir staking contract
    IstdeUSD public immutable STAKING_VAULT;

    /// @notice Elixir deUSD stablecoin
    deUSD public immutable DEUSD_TOKEN;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Elixir minting contract
    deUSDMinting public mintContract;

    /// @notice only address authorized to invoke transferInRewards
    address public operator;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        deUSDMinting _mint_contract,
        IstdeUSD _staking_vault,
        deUSD _deusd,
        address[] memory _assets,
        address _admin,
        address _operator
    ) Ownable(_admin) {
        // Constructor params check
        if (address(_mint_contract) == address(0)) revert InvalidZeroAddress();
        if (address(_staking_vault) == address(0)) revert InvalidZeroAddress();
        if (address(_deusd) == address(0)) revert InvalidZeroAddress();
        if (_assets.length == 0) revert NoAssetsProvided();
        if (address(_operator) == address(0)) revert InvalidZeroAddress();

        // Assign immutables
        STAKING_VAULT = _staking_vault;
        DEUSD_TOKEN = _deusd;

        // Assign minting contract
        mintContract = _mint_contract;

        // Set the operator and delegate the signer
        setOperator(_operator);

        // Approve the assets to the minting contract
        approveToMintContract(_assets);

        // Also approve deUSD to the staking contract to allow the transferInRewards call
        IERC20(address(DEUSD_TOKEN)).safeIncreaseAllowance(address(STAKING_VAULT), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice only the operator can call transferInRewards in order to transfer deUSD to the staking contract
    /// @param _rewardsAmount the amount of deUSD to send
    /// @dev In order to use this function, we need to set this contract as the REWARDER_ROLE in the staking contract
    ///      No need to check that the input amount is not 0, since we already check this in the staking contract
    function transferInRewards(uint256 _rewardsAmount) external {
        if (msg.sender != operator) revert OnlyOperator();

        // Check that this contract holds enough deUSD balance to transfer
        if (DEUSD_TOKEN.balanceOf(address(this)) < _rewardsAmount) revert InsufficientFunds();

        STAKING_VAULT.transferInRewards(_rewardsAmount);
    }

    /// @notice owner can rescue tokens that were accidentally sent to the contract
    /// @param _token the token to transfer
    /// @param _to the address to send the tokens to
    /// @param _amount the amount of tokens to send
    /// @dev only available for the owner
    function rescueTokens(address _token, address _to, uint256 _amount) external nonReentrant onlyOwner {
        if (_token == address(0)) revert InvalidZeroAddress();
        if (_to == address(0)) revert InvalidZeroAddress();
        if (_amount == 0) revert InvalidAmount();

        // contract should never hold ETH
        if (_token == _ETH_ADDRESS) {
            (bool success,) = _to.call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
        emit TokensRescued(_token, _to, _amount);
    }

    /// @notice sets a new minting contract
    /// @param _newMintingContract new minting contract
    /// @dev only available for the owner, high probability that this function never gets called
    /// @dev revoke approvals for previous contract after calling this function
    function setMintingContract(deUSDMinting _newMintingContract) external onlyOwner {
        if (address(_newMintingContract) == address(0)) revert InvalidZeroAddress();
        emit MintingContractUpdated(address(_newMintingContract), address(mintContract));
        mintContract = _newMintingContract;
    }

    /// @notice approves the desired assets to the minting contract
    /// @param _assets assets to approve
    /// @dev only available for the owner
    function approveToMintContract(address[] memory _assets) public onlyOwner {
        // Max approval granted to the Minting contract
        for (uint256 i = 0; i < _assets.length; i++) {
            IERC20(_assets[i]).safeIncreaseAllowance(address(mintContract), type(uint256).max);
        }
    }

    /// @notice revokes the previously granted ERC20 approvals from a specific address
    /// @param _assets assets to revoke
    /// @param _target address to revoke the approvals from
    /// @dev only available for the owner. Can't revoke the approvals from the current minting contract
    function revokeApprovals(address[] memory _assets, address _target) external onlyOwner {
        if (_assets.length == 0) revert NoAssetsProvided();
        if (_target == address(0)) revert InvalidZeroAddress();
        if (_target == address(mintContract)) revert InvalidAddressCurrentMintContract();

        // Revoke approvals from specified address
        for (uint256 i = 0; i < _assets.length; i++) {
            IERC20(_assets[i]).forceApprove(_target, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice sets a new operator and delegated signer, removing the previous one
    /// @param _newOperator new operator and delegated signer
    /// @dev only available for the owner. We allow the address(0) as a new operator
    ///      in case that the key is exposed and we just want to remove the
    ///      as soon as possible being able to set to 0
    function setOperator(address _newOperator) public onlyOwner {
        // Remove previous delegated signer
        mintContract.removeDelegatedSigner(operator);

        // Delegate the new signer
        mintContract.setDelegatedSigner(_newOperator);

        emit OperatorUpdated(_newOperator, operator);
        operator = _newOperator;
    }

    /// @notice prevents the owner from renouncing the owner role
    function renounceOwnership() public view override onlyOwner {
        revert CantRenounceOwnership();
    }
}
