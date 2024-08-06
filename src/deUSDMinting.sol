// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin/utils/cryptography/MessageHashUtils.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {SingleAdminAccessControl} from "src/SingleAdminAccessControl.sol";
import {IdeUSDMinting} from "src/interfaces/IdeUSDMinting.sol";
import {deUSD} from "src/deUSD.sol";
import {IWETH9} from "src/interfaces/IWETH9.sol";

/// @title deUSDMinting
/// @notice This contract mints and redeems deUSD in a single, atomic, trustless transaction
contract deUSDMinting is
    IdeUSDMinting,
    Initializable,
    UUPSUpgradeable,
    SingleAdminAccessControl,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice order type
    bytes32 private constant ORDER_TYPE = keccak256(
        "Order(uint8 order_type,uint256 expiry,uint256 nonce,address benefactor,address beneficiary,address collateral_asset,uint256 collateral_amount,uint256 deUSD_amount)"
    );

    /// @notice role enabling to invoke mint
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice role enabling to invoke redeem
    bytes32 private constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");

    /// @notice role enabling to transfer collateral to custody wallets
    bytes32 private constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    /// @notice role enabling to disable mint and redeem and remove minters and redeemers in an emergency
    bytes32 private constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice address denoting native ether
    address private constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice required ratio for route
    uint256 private constant ROUTE_REQUIRED_RATIO = 10_000;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice WETH
    IWETH9 private WETH;

    /// @notice deUSD
    deUSD public deusd;

    /// @notice Supported assets
    EnumerableSet.AddressSet internal _supportedAssets;

    // @notice custodian addresses
    EnumerableSet.AddressSet internal _custodianAddresses;

    /// @notice user deduplication
    mapping(address => mapping(uint256 => uint256)) private _orderBitmaps;

    /// @notice deUSD minted per block
    mapping(uint256 => uint256) public mintedPerBlock;
    /// @notice deUSD redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    /// @notice For smart contracts to delegate signing to EOA address
    mapping(address => mapping(address => DelegatedSignerStatus)) public delegatedSigner;

    /// @notice max minted deUSD allowed per block
    uint256 public maxMintPerBlock;
    /// @notice max redeemed deUSD allowed per block
    uint256 public maxRedeemPerBlock;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice ensure that the already minted deUSD in the actual block plus the amount to be minted is below the maxMintPerBlock var
    /// @param mintAmount The deUSD amount to be minted
    modifier belowMaxMintPerBlock(uint256 mintAmount) {
        if (mintedPerBlock[block.number] + mintAmount > maxMintPerBlock) revert MaxMintPerBlockExceeded();
        _;
    }

    /// @notice ensure that the already redeemed deUSD in the actual block plus the amount to be redeemed is below the maxRedeemPerBlock var
    /// @param redeemAmount The deUSD amount to be redeemed
    modifier belowMaxRedeemPerBlock(uint256 redeemAmount) {
        if (redeemedPerBlock[block.number] + redeemAmount > maxRedeemPerBlock) revert MaxRedeemPerBlockExceeded();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Prevent the implementation contract from being initialized.
    /// @dev The proxy contract state will still be able to call this function because the constructor does not affect the proxy state.
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    function initialize(
        deUSD _deUSD,
        IWETH9 _weth,
        address[] memory _assets,
        address[] memory _custodians,
        address _admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    ) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        __EIP712_init("deUSDMinting", "1");

        if (address(_deUSD) == address(0)) revert InvaliddeUSDAddress();
        if (address(_weth) == address(0)) revert InvalidZeroAddress();
        if (_assets.length == 0) revert NoAssetsProvided();
        if (_admin == address(0)) revert InvalidZeroAddress();
        deusd = _deUSD;
        WETH = _weth;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < _assets.length; i++) {
            addSupportedAsset(_assets[i]);
        }

        for (uint256 j = 0; j < _custodians.length; j++) {
            addCustodianAddress(_custodians[j]);
        }

        // Set the max mint/redeem limits per block
        _setMaxMintPerBlock(_maxMintPerBlock);
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);

        if (msg.sender != _admin) {
            _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        }

        emit deUSDSet(address(_deUSD));
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fallback function to receive ether
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Mint deUSDs from assets
    /// @param order struct containing order details and confirmation from server
    /// @param signature signature of the taker
    function mint(Order calldata order, Route calldata route, Signature calldata signature)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
        belowMaxMintPerBlock(order.deUSD_amount)
    {
        if (order.order_type != OrderType.MINT) revert InvalidOrder();
        verifyOrder(order, signature);
        if (!verifyRoute(route)) revert InvalidRoute();
        _deduplicateOrder(order.benefactor, order.nonce);
        // Add to the minted amount in this block
        mintedPerBlock[block.number] += order.deUSD_amount;
        _transferCollateral(
            order.collateral_amount, order.collateral_asset, order.benefactor, route.addresses, route.ratios
        );
        deusd.mint(order.beneficiary, order.deUSD_amount);
        emit Mint(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.deUSD_amount
        );
    }

    /// @notice Mint stablecoins from assets
    /// @param order struct containing order details and confirmation from server
    /// @param signature signature of the taker
    function mintWETH(Order calldata order, Route calldata route, Signature calldata signature)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
        belowMaxMintPerBlock(order.deUSD_amount)
    {
        if (order.order_type != OrderType.MINT) revert InvalidOrder();
        verifyOrder(order, signature);
        if (!verifyRoute(route)) revert InvalidRoute();
        _deduplicateOrder(order.benefactor, order.nonce);
        // Add to the minted amount in this block
        mintedPerBlock[block.number] += order.deUSD_amount;
        // Checks that the collateral asset is WETH also
        _transferEthCollateral(
            order.collateral_amount, order.collateral_asset, order.benefactor, route.addresses, route.ratios
        );
        deusd.mint(order.beneficiary, order.deUSD_amount);
        emit Mint(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.deUSD_amount
        );
    }

    /// @notice Redeem deUSDs for assets
    /// @param order struct containing order details and confirmation from server
    /// @param signature signature of the taker
    function redeem(Order calldata order, Signature calldata signature)
        external
        nonReentrant
        onlyRole(REDEEMER_ROLE)
        belowMaxRedeemPerBlock(order.deUSD_amount)
    {
        if (order.order_type != OrderType.REDEEM) revert InvalidOrder();
        verifyOrder(order, signature);
        _deduplicateOrder(order.benefactor, order.nonce);
        // Add to the redeemed amount in this block
        redeemedPerBlock[block.number] += order.deUSD_amount;
        deusd.burnFrom(order.benefactor, order.deUSD_amount);
        _transferToBeneficiary(order.beneficiary, order.collateral_asset, order.collateral_amount);
        emit Redeem(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.deUSD_amount
        );
    }

    /// @notice Sets the max mintPerBlock limit
    function setMaxMintPerBlock(uint256 _maxMintPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxMintPerBlock(_maxMintPerBlock);
    }

    /// @notice Sets the max redeemPerBlock limit
    function setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /// @notice Disables the mint and redeem
    function disableMintRedeem() external onlyRole(GATEKEEPER_ROLE) {
        _setMaxMintPerBlock(0);
        _setMaxRedeemPerBlock(0);
    }

    /// @notice Enables smart contracts to delegate an address for signing
    function setDelegatedSigner(address _delegateTo) external {
        delegatedSigner[_delegateTo][msg.sender] = DelegatedSignerStatus.PENDING;
        emit DelegatedSignerInitiated(_delegateTo, msg.sender);
    }

    /// @notice The delegated address to confirm delegation
    function confirmDelegatedSigner(address _delegatedBy) external {
        if (delegatedSigner[msg.sender][_delegatedBy] != DelegatedSignerStatus.PENDING) {
            revert DelegationNotInitiated();
        }
        delegatedSigner[msg.sender][_delegatedBy] = DelegatedSignerStatus.ACCEPTED;
        emit DelegatedSignerAdded(msg.sender, _delegatedBy);
    }

    /// @notice Enables smart contracts to undelegate an address for signing
    function removeDelegatedSigner(address _removedSigner) external {
        delegatedSigner[_removedSigner][msg.sender] = DelegatedSignerStatus.REJECTED;
        emit DelegatedSignerRemoved(_removedSigner, msg.sender);
    }

    /// @notice transfers an asset to a custody wallet
    function transferToCustody(address wallet, address asset, uint256 amount)
        external
        nonReentrant
        onlyRole(COLLATERAL_MANAGER_ROLE)
    {
        if (wallet == address(0) || !_custodianAddresses.contains(wallet)) revert InvalidAddress();
        if (asset == NATIVE_TOKEN) {
            (bool success,) = wallet.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(asset).safeTransfer(wallet, amount);
        }
        emit CustodyTransfer(wallet, asset, amount);
    }

    /// @notice Removes an asset from the supported assets list
    function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_supportedAssets.remove(asset)) revert InvalidAssetAddress();
        emit AssetRemoved(asset);
    }

    /// @notice Checks if an asset is supported.
    function isSupportedAsset(address asset) external view returns (bool) {
        return _supportedAssets.contains(asset);
    }

    /// @notice Removes an custodian from the custodian address list
    function removeCustodianAddress(address custodian) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_custodianAddresses.remove(custodian)) revert InvalidCustodianAddress();
        emit CustodianAddressRemoved(custodian);
    }

    /// @notice Removes the minter role from an account, this can ONLY be executed by the gatekeeper role
    /// @param minter The address to remove the minter role from
    function removeMinterRole(address minter) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
    }

    /// @notice Removes the redeemer role from an account, this can ONLY be executed by the gatekeeper role
    /// @param redeemer The address to remove the redeemer role from
    function removeRedeemerRole(address redeemer) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(REDEEMER_ROLE, redeemer);
    }

    /// @notice Removes the collateral manager role from an account, this can ONLY be executed by the gatekeeper role
    /// @param collateralManager The address to remove the collateralManager role from
    function removeCollateralManagerRole(address collateralManager) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(COLLATERAL_MANAGER_ROLE, collateralManager);
    }

    /*//////////////////////////////////////////////////////////////
                              PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds an asset to the supported assets list.
    function addSupportedAsset(address asset) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (asset == address(0) || asset == address(deusd) || !_supportedAssets.add(asset)) {
            revert InvalidAssetAddress();
        }
        emit AssetAdded(asset);
    }

    /// @notice Adds an custodian to the supported custodians list.
    function addCustodianAddress(address custodian) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (custodian == address(0) || custodian == address(deusd) || !_custodianAddresses.add(custodian)) {
            revert InvalidCustodianAddress();
        }
        emit CustodianAddressAdded(custodian);
    }

    /// @notice hash an Order struct
    function hashOrder(Order calldata order) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(encodeOrder(order)));
    }

    function encodeOrder(Order calldata order) public pure returns (bytes memory) {
        return abi.encode(
            ORDER_TYPE,
            order.order_type,
            order.expiry,
            order.nonce,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.deUSD_amount
        );
    }

    /// @notice assert validity of signed order
    function verifyOrder(Order calldata order, Signature calldata signature)
        public
        view
        returns (bytes32 taker_order_hash)
    {
        taker_order_hash = hashOrder(order);
        address signer = ECDSA.recover(taker_order_hash, signature.signature_bytes);
        if (
            !(signer == order.benefactor || delegatedSigner[signer][order.benefactor] == DelegatedSignerStatus.ACCEPTED)
        ) {
            revert InvalidSignature();
        }
        if (order.beneficiary == address(0)) revert InvalidAddress();
        if (order.collateral_amount == 0) revert InvalidAmount();
        if (order.deUSD_amount == 0) revert InvalidAmount();
        if (block.timestamp > order.expiry) revert SignatureExpired();
    }

    /// @notice assert validity of route object per type
    function verifyRoute(Route calldata route) public view returns (bool) {
        uint256 totalRatio = 0;
        if (route.addresses.length != route.ratios.length) {
            return false;
        }
        if (route.addresses.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < route.addresses.length; i++) {
            if (
                !_custodianAddresses.contains(route.addresses[i]) || route.addresses[i] == address(0)
                    || route.ratios[i] == 0
            ) {
                return false;
            }
            totalRatio += route.ratios[i];
        }
        return (totalRatio == ROUTE_REQUIRED_RATIO);
    }
    /// @notice assert validity of route object per type

    function verifyRoute(Route calldata route, OrderType orderType) public view returns (bool) {
        // routes only used to mint
        if (orderType == OrderType.REDEEM) {
            return true;
        }
        uint256 totalRatio = 0;
        if (route.addresses.length != route.ratios.length) {
            return false;
        }
        if (route.addresses.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < route.addresses.length; ++i) {
            if (
                !_custodianAddresses.contains(route.addresses[i]) || route.addresses[i] == address(0)
                    || route.ratios[i] == 0
            ) {
                return false;
            }
            totalRatio += route.ratios[i];
        }
        if (totalRatio != 10_000) {
            return false;
        }
        return true;
    }

    /// @notice verify validity of nonce by checking its presence
    /// @dev invalidatorSlot from nonce could collide if nonces are sufficently big enough (> 2^64) although very unlikely
    function verifyNonce(address sender, uint256 nonce) public view returns (uint256, uint256, uint256) {
        if (nonce == 0 || nonce > type(uint64).max) revert InvalidNonce();
        uint256 invalidatorSlot = uint64(nonce) >> 8;
        uint256 invalidatorBit = 1 << uint8(nonce);
        uint256 invalidator = _orderBitmaps[sender][invalidatorSlot];
        if (invalidator & invalidatorBit != 0) revert InvalidNonce();

        return (invalidatorSlot, invalidator, invalidatorBit);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice deduplication of taker order
    function _deduplicateOrder(address sender, uint256 nonce) private {
        (uint256 invalidatorSlot, uint256 invalidator, uint256 invalidatorBit) = verifyNonce(sender, nonce);
        _orderBitmaps[sender][invalidatorSlot] = invalidator | invalidatorBit;
    }
    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice transfer supported asset to beneficiary address
    function _transferToBeneficiary(address beneficiary, address asset, uint256 amount) internal {
        if (asset == NATIVE_TOKEN) {
            if (address(this).balance < amount) revert InvalidAmount();
            (bool success,) = (beneficiary).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (!_supportedAssets.contains(asset)) revert UnsupportedAsset();
            IERC20(asset).safeTransfer(beneficiary, amount);
        }
    }

    /// @notice transfer supported asset to array of custody addresses per defined ratio
    function _transferCollateral(
        uint256 amount,
        address asset,
        address benefactor,
        address[] calldata addresses,
        uint256[] calldata ratios
    ) internal {
        // cannot mint using unsupported asset or native ETH even if it is supported for redemptions
        if (!_supportedAssets.contains(asset) || asset == NATIVE_TOKEN) revert UnsupportedAsset();
        IERC20 token = IERC20(asset);
        uint256 totalTransferred = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 amountToTransfer = (amount * ratios[i]) / ROUTE_REQUIRED_RATIO;
            token.safeTransferFrom(benefactor, addresses[i], amountToTransfer);
            totalTransferred += amountToTransfer;
        }
        uint256 remainingBalance = amount - totalTransferred;
        if (remainingBalance > 0) {
            token.safeTransferFrom(benefactor, addresses[addresses.length - 1], remainingBalance);
        }
    }

    /// @notice transfer supported asset to array of custody addresses per defined ratio
    function _transferEthCollateral(
        uint256 amount,
        address asset,
        address benefactor,
        address[] calldata addresses,
        uint256[] calldata ratios
    ) internal {
        if (!_supportedAssets.contains(asset) || asset == NATIVE_TOKEN || asset != address(WETH)) {
            revert UnsupportedAsset();
        }
        IERC20 token = IERC20(asset);
        token.safeTransferFrom(benefactor, address(this), amount);

        WETH.withdraw(amount);

        uint256 totalTransferred = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 amountToTransfer = (amount * ratios[i]) / ROUTE_REQUIRED_RATIO;
            (bool success,) = addresses[i].call{value: amountToTransfer}("");
            if (!success) revert TransferFailed();
            totalTransferred += amountToTransfer;
        }
        uint256 remainingBalance = amount - totalTransferred;
        if (remainingBalance > 0) {
            (bool success,) = addresses[addresses.length - 1].call{value: remainingBalance}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Sets the max mintPerBlock limit
    function _setMaxMintPerBlock(uint256 _maxMintPerBlock) internal {
        uint256 oldMaxMintPerBlock = maxMintPerBlock;
        maxMintPerBlock = _maxMintPerBlock;
        emit MaxMintPerBlockChanged(oldMaxMintPerBlock, maxMintPerBlock);
    }

    /// @notice Sets the max redeemPerBlock limit
    function _setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) internal {
        uint256 oldMaxRedeemPerBlock = maxRedeemPerBlock;
        maxRedeemPerBlock = _maxRedeemPerBlock;
        emit MaxRedeemPerBlockChanged(oldMaxRedeemPerBlock, maxRedeemPerBlock);
    }

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
