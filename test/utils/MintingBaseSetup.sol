// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {Utils} from "test/utils/Utils.sol";

import "test/mock/MockToken.sol";
import "src/deUSD.sol";
import "src/interfaces/IdeUSDMinting.sol";
import "src/interfaces/ISingleAdminAccessControl.sol";
import "src/deUSDMinting.sol";

import "src/interfaces/IdeUSD.sol";
import "test/mock/MockWETH.sol";
import "src/interfaces/IWETH9.sol";

contract MintingBaseSetup is Test, IdeUSD {
    Utils internal utils;
    deUSD internal deUSDToken;
    MockToken internal stETHToken;
    MockToken internal cbETHToken;
    MockToken internal rETHToken;
    MockToken internal USDCToken;
    MockToken internal USDTToken;
    MockToken internal token;
    deUSDMinting internal deUSDMintingContract;
    SigUtils internal sigUtils;
    SigUtils internal sigUtilsdeUSD;
    IWETH9 internal weth;

    uint256 internal ownerPrivateKey;
    uint256 internal newOwnerPrivateKey;
    uint256 internal minterPrivateKey;
    uint256 internal redeemerPrivateKey;
    uint256 internal maker1PrivateKey;
    uint256 internal maker2PrivateKey;
    uint256 internal benefactorPrivateKey;
    uint256 internal beneficiaryPrivateKey;
    uint256 internal trader1PrivateKey;
    uint256 internal trader2PrivateKey;
    uint256 internal gatekeeperPrivateKey;
    uint256 internal bobPrivateKey;
    uint256 internal custodian1PrivateKey;
    uint256 internal custodian2PrivateKey;
    uint256 internal randomerPrivateKey;

    address internal owner;
    address internal newOwner;
    address internal minter;
    address internal redeemer;
    address internal collateralManager;
    address internal benefactor;
    address internal beneficiary;
    address internal maker1;
    address internal maker2;
    address internal trader1;
    address internal trader2;
    address internal gatekeeper;
    address internal bob;
    address internal custodian1;
    address internal custodian2;
    address internal randomer;

    address[] assets;
    address[] custodians;

    address internal NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Roles references
    bytes32 internal minterRole = keccak256("MINTER_ROLE");
    bytes32 internal gatekeeperRole = keccak256("GATEKEEPER_ROLE");
    bytes32 internal adminRole = 0x00;
    bytes32 internal redeemerRole = keccak256("REDEEMER_ROLE");
    bytes32 internal collateralManagerRole = keccak256("COLLATERAL_MANAGER_ROLE");

    // error encodings
    bytes internal InvalidAddress = abi.encodeWithSelector(IdeUSDMinting.InvalidAddress.selector);
    bytes internal InvaliddeUSDAddress = abi.encodeWithSelector(IdeUSDMinting.InvaliddeUSDAddress.selector);
    bytes internal InvalidAssetAddress = abi.encodeWithSelector(IdeUSDMinting.InvalidAssetAddress.selector);
    bytes internal InvalidOrder = abi.encodeWithSelector(IdeUSDMinting.InvalidOrder.selector);
    bytes internal InvalidAmount = abi.encodeWithSelector(IdeUSDMinting.InvalidAmount.selector);
    bytes internal InvalidRoute = abi.encodeWithSelector(IdeUSDMinting.InvalidRoute.selector);
    bytes internal InvalidAdminChange = abi.encodeWithSelector(ISingleAdminAccessControl.InvalidAdminChange.selector);
    bytes internal UnsupportedAsset = abi.encodeWithSelector(IdeUSDMinting.UnsupportedAsset.selector);
    bytes internal NoAssetsProvided = abi.encodeWithSelector(IdeUSDMinting.NoAssetsProvided.selector);
    bytes internal InvalidSignature = abi.encodeWithSelector(IdeUSDMinting.InvalidSignature.selector);
    bytes internal InvalidNonce = abi.encodeWithSelector(IdeUSDMinting.InvalidNonce.selector);
    bytes internal SignatureExpired = abi.encodeWithSelector(IdeUSDMinting.SignatureExpired.selector);
    bytes internal MaxMintPerBlockExceeded = abi.encodeWithSelector(IdeUSDMinting.MaxMintPerBlockExceeded.selector);
    bytes internal MaxRedeemPerBlockExceeded = abi.encodeWithSelector(IdeUSDMinting.MaxRedeemPerBlockExceeded.selector);
    // deUSD error encodings
    bytes internal OnlyMinterErr = abi.encodeWithSelector(IdeUSD.OnlyMinter.selector);
    bytes internal ZeroAddressExceptionErr = abi.encodeWithSelector(IdeUSD.ZeroAddressException.selector);
    bytes internal CantRenounceOwnershipErr = abi.encodeWithSelector(IdeUSD.CantRenounceOwnership.selector);

    bytes32 internal constant ROUTE_TYPE = keccak256("Route(address[] addresses,uint256[] ratios)");
    bytes32 internal constant ORDER_TYPE = keccak256(
        "Order(uint256 expiry,uint256 nonce,address benefactor,address beneficiary,address asset,uint256 base_amount,uint256 quote_amount)"
    );

    uint256 internal _slippageRange = 50000000000000000;
    uint256 internal _stETHToDeposit = 50 * 10 ** 18;
    uint256 internal _stETHToWithdraw = 30 * 10 ** 18;
    uint256 internal _deUSDToMint = 8.75 * 10 ** 23;
    uint256 internal _maxMintPerBlock = 10e23;
    uint256 internal _maxRedeemPerBlock = _maxMintPerBlock;

    // Declared at contract level to avoid stack too deep
    SigUtils.Permit public permit;
    IdeUSDMinting.Order public mint;

    /// @notice packs r, s, v into signature bytes
    function _packRsv(bytes32 r, bytes32 s, uint8 v) internal pure returns (bytes memory) {
        bytes memory sig = new bytes(65);
        assembly {
            mstore(add(sig, 32), r)
            mstore(add(sig, 64), s)
            mstore8(add(sig, 96), v)
        }
        return sig;
    }

    function setUp() public virtual {
        utils = new Utils();

        deUSDToken = deUSD(
            address(
                new ERC1967Proxy(address(new deUSD()), abi.encodeWithSignature("initialize(address)", address(this)))
            )
        );

        weth = IWETH9(address(new WETH9()));
        stETHToken = new MockToken("Staked ETH", "sETH", 18, msg.sender);
        cbETHToken = new MockToken("Coinbase ETH", "cbETH", 18, msg.sender);
        rETHToken = new MockToken("Rocket Pool ETH", "rETH", 18, msg.sender);
        USDCToken = new MockToken("United States Dollar Coin", "USDC", 6, msg.sender);
        USDTToken = new MockToken("United States Dollar Token", "USDT", 18, msg.sender);

        sigUtils = new SigUtils(stETHToken.DOMAIN_SEPARATOR());
        sigUtilsdeUSD = new SigUtils(deUSDToken.DOMAIN_SEPARATOR());

        assets = new address[](6);
        assets[0] = address(stETHToken);
        assets[1] = address(cbETHToken);
        assets[2] = address(rETHToken);
        assets[3] = address(USDCToken);
        assets[4] = address(USDTToken);
        assets[5] = NATIVE_TOKEN;

        ownerPrivateKey = 0xA11CE;
        newOwnerPrivateKey = 0xA14CE;
        minterPrivateKey = 0xB44DE;
        redeemerPrivateKey = 0xB45DE;
        maker1PrivateKey = 0xA13CE;
        maker2PrivateKey = 0xA14CE;
        benefactorPrivateKey = 0x1DC;
        beneficiaryPrivateKey = 0x1DAC;
        trader1PrivateKey = 0x1DE;
        trader2PrivateKey = 0x1DEA;
        gatekeeperPrivateKey = 0x1DEA1;
        bobPrivateKey = 0x1DEA2;
        custodian1PrivateKey = 0x1DCDE;
        custodian2PrivateKey = 0x1DCCE;
        randomerPrivateKey = 0x1DECC;

        owner = vm.addr(ownerPrivateKey);
        newOwner = vm.addr(newOwnerPrivateKey);
        minter = vm.addr(minterPrivateKey);
        redeemer = vm.addr(redeemerPrivateKey);
        maker1 = vm.addr(maker1PrivateKey);
        maker2 = vm.addr(maker2PrivateKey);
        benefactor = vm.addr(benefactorPrivateKey);
        beneficiary = vm.addr(beneficiaryPrivateKey);
        trader1 = vm.addr(trader1PrivateKey);
        trader2 = vm.addr(trader2PrivateKey);
        gatekeeper = vm.addr(gatekeeperPrivateKey);
        bob = vm.addr(bobPrivateKey);
        custodian1 = vm.addr(custodian1PrivateKey);
        custodian2 = vm.addr(custodian2PrivateKey);
        randomer = vm.addr(randomerPrivateKey);
        collateralManager = makeAddr("collateralManager");

        custodians = new address[](1);
        custodians[0] = custodian1;

        vm.label(minter, "minter");
        vm.label(redeemer, "redeemer");
        vm.label(owner, "owner");
        vm.label(maker1, "maker1");
        vm.label(maker2, "maker2");
        vm.label(benefactor, "benefactor");
        vm.label(beneficiary, "beneficiary");
        vm.label(trader1, "trader1");
        vm.label(trader2, "trader2");
        vm.label(gatekeeper, "gatekeeper");
        vm.label(bob, "bob");
        vm.label(custodian1, "custodian1");
        vm.label(custodian2, "custodian2");
        vm.label(randomer, "randomer");

        // Set the roles
        vm.startPrank(owner);
        deUSDMintingContract = deUSDMinting(
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
                            owner,
                            _maxMintPerBlock,
                            _maxRedeemPerBlock
                        )
                    )
                )
            )
        );

        deUSDMintingContract.grantRole(gatekeeperRole, gatekeeper);
        deUSDMintingContract.grantRole(minterRole, minter);
        deUSDMintingContract.grantRole(redeemerRole, redeemer);
        deUSDMintingContract.grantRole(collateralManagerRole, collateralManager);

        // Set the max mint per block
        deUSDMintingContract.setMaxMintPerBlock(_maxMintPerBlock);
        // Set the max redeem per block
        deUSDMintingContract.setMaxRedeemPerBlock(_maxRedeemPerBlock);

        // Add self as approved custodian
        deUSDMintingContract.addCustodianAddress(address(deUSDMintingContract));

        // Mint stEth to the benefactor in order to test
        stETHToken.mint(_stETHToDeposit, benefactor);
        vm.stopPrank();

        deUSDToken.setMinter(address(deUSDMintingContract));
    }

    function signOrder(uint256 key, bytes32 digest, IdeUSDMinting.SignatureType sigType)
        public
        pure
        returns (IdeUSDMinting.Signature memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        bytes memory sigBytes = _packRsv(r, s, v);

        IdeUSDMinting.Signature memory signature =
            IdeUSDMinting.Signature({signature_type: sigType, signature_bytes: sigBytes});

        return signature;
    }

    // Generic mint setup reused in the tests to reduce lines of code
    function mint_setup(
        uint256 deUSDAmount,
        uint256 collateralAmount,
        IERC20 collateralToken,
        uint256 nonce,
        bool multipleMints
    )
        public
        returns (
            IdeUSDMinting.Order memory order,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        )
    {
        order = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.MINT,
            expiry: block.timestamp + 10 minutes,
            nonce: nonce,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(collateralToken),
            deUSD_amount: deUSDAmount,
            collateral_amount: collateralAmount
        });

        address[] memory targets = new address[](1);
        targets[0] = address(deUSDMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        route = IdeUSDMinting.Route({addresses: targets, ratios: ratios});

        vm.startPrank(benefactor);
        bytes32 digest1 = deUSDMintingContract.hashOrder(order);
        takerSignature = signOrder(benefactorPrivateKey, digest1, IdeUSDMinting.SignatureType.EIP712);
        collateralToken.approve(address(deUSDMintingContract), collateralAmount);
        vm.stopPrank();

        if (!multipleMints) {
            assertEq(deUSDToken.balanceOf(beneficiary), 0, "Mismatch in deUSD balance");
            assertEq(collateralToken.balanceOf(address(deUSDMintingContract)), 0, "Mismatch in collateral balance");
            assertEq(collateralToken.balanceOf(benefactor), collateralAmount, "Mismatch in collateral balance");
        }
    }

    // Generic redeem setup reused in the tests to reduce lines of code
    function redeem_setup(
        uint256 deUSDAmount,
        uint256 collateralAmount,
        IERC20 collateralAsset,
        uint256 nonce,
        bool multipleRedeem
    ) public returns (IdeUSDMinting.Order memory redeemOrder, IdeUSDMinting.Signature memory takerSignature2) {
        (
            IdeUSDMinting.Order memory mintOrder,
            IdeUSDMinting.Signature memory takerSignature,
            IdeUSDMinting.Route memory route
        ) = mint_setup(deUSDAmount, collateralAmount, collateralAsset, nonce, false);

        vm.prank(minter);
        deUSDMintingContract.mint(mintOrder, route, takerSignature);

        //redeem
        redeemOrder = IdeUSDMinting.Order({
            order_type: IdeUSDMinting.OrderType.REDEEM,
            expiry: block.timestamp + 10 minutes,
            nonce: nonce + 1,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(collateralAsset),
            deUSD_amount: deUSDAmount,
            collateral_amount: collateralAmount
        });

        // taker
        vm.startPrank(beneficiary);
        deUSDToken.approve(address(deUSDMintingContract), deUSDAmount);

        bytes32 digest3 = deUSDMintingContract.hashOrder(redeemOrder);
        takerSignature2 = signOrder(beneficiaryPrivateKey, digest3, IdeUSDMinting.SignatureType.EIP712);
        vm.stopPrank();

        vm.startPrank(owner);
        deUSDMintingContract.grantRole(redeemerRole, redeemer);
        vm.stopPrank();

        if (!multipleRedeem) {
            assertEq(
                collateralAsset.balanceOf(address(deUSDMintingContract)),
                collateralAmount,
                "Mismatch in collateral balance"
            );
            assertEq(collateralAsset.balanceOf(beneficiary), 0, "Mismatch in collateral balance");
            assertEq(deUSDToken.balanceOf(beneficiary), deUSDAmount, "Mismatch in deUSD balance");
        }
    }
}
