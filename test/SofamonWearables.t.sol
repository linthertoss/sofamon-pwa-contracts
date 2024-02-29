// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SofamonWearables.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestBlast} from "../test/TestBlast.sol";
import {TestBlastPoints} from "../test/TestBlastPoints.sol";

contract SofamonWearablesTest is Test {
    using ECDSA for bytes32;

    event ProtocolFeeDestinationUpdated(address feeDestination);

    event ProtocolFeePercentUpdated(uint256 feePercent);

    event CreatorFeePercentUpdated(uint256 feePercent);

    event CreateSignerUpdated(address signer);

    event WearableSaleStateUpdated(bytes32 wearablesSubject, SofamonWearables.SaleStates saleState);

    event NonceUpdated(address user, uint256 nonce);

    event WearableCreated(
        address creator,
        bytes32 subject,
        string name,
        string category,
        string description,
        string imageURI,
        uint256 curveAdjustmentFactor,
        SofamonWearables.SaleStates state
    );

    event Trade(
        address trader,
        bytes32 subject,
        bool isBuy,
        bool isPublic,
        uint256 wearableAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 creatorEthAmount,
        uint256 supply
    );

    event WearableTransferred(address from, address to, bytes32 subject, uint256 amount);

    ERC1967Proxy public proxy;
    SofamonWearables public proxySofa;

    uint256 internal signer1Privatekey = 0x1;
    uint256 internal signer2Privatekey = 0x2;

    address BLAST = 0x4300000000000000000000000000000000000002;
    address BLAST_POINTS = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;

    address owner = address(0x11);
    address protocolFeeDestination = address(0x22);
    address signer1 = vm.addr(signer1Privatekey);
    address signer2 = vm.addr(signer2Privatekey);
    address creator1 = address(0xa);
    address creator2 = address(0xb);
    address user1 = address(0xc);
    address user2 = address(0xd);

    function setUp() public {
        TestBlast testBlast = new TestBlast();
        TestBlastPoints testBlastPoints = new TestBlastPoints();
        vm.etch(BLAST, address(testBlast).code);
        vm.etch(BLAST_POINTS, address(testBlastPoints).code);

        vm.startPrank(owner);
        SofamonWearables sofa = new SofamonWearables();
        proxy = new ERC1967Proxy(address(sofa), "");
        proxySofa = SofamonWearables(address(proxy));
        proxySofa.initialize(owner, owner, signer1);
    }

    function testSofamonWearablesUpgradable() public {
        // deploy new sofa contract
        vm.startPrank(owner);
        SofamonWearables sofav2 = new SofamonWearables();
        SofamonWearables(address(proxy)).upgradeTo(address(sofav2));
        SofamonWearables proxySofav2 = SofamonWearables(address(proxy));
        vm.stopPrank();
        assertEq(proxySofav2.owner(), owner);
    }

    function testSetProtocolFeeAndCreatorFee() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeePercentUpdated(0.05 ether);
        proxySofa.setProtocolFeePercent(0.05 ether);
        vm.expectEmit(true, true, true, true);
        emit CreatorFeePercentUpdated(0.05 ether);
        proxySofa.setCreatorFeePercent(0.05 ether);
        assertEq(proxySofa.protocolFeePercent(), 0.05 ether);
        assertEq(proxySofa.creatorFeePercent(), 0.05 ether);
    }

    function testSetProtocolFeeDestination() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeDestinationUpdated(protocolFeeDestination);
        proxySofa.setProtocolFeeDestination(protocolFeeDestination);
        assertEq(proxySofa.protocolFeeDestination(), protocolFeeDestination);
    }

    function testSetSigner() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit CreateSignerUpdated(signer2);
        proxySofa.setCreateSigner(signer2);
        assertEq(proxySofa.createSigner(), signer2);
    }

    function testCreateWearable() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PUBLIC
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();
    }

    function testSetWearableSalesState() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PUBLIC
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit WearableSaleStateUpdated(wearablesSubject, SofamonWearables.SaleStates.PRIVATE);
        proxySofa.setWearableSalesState(wearablesSubject, SofamonWearables.SaleStates.PRIVATE);
        vm.stopPrank();
    }

    function testBuyWearables() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PUBLIC
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        assertEq(user1.balance, 1 ether);
        uint256 buyPrice = proxySofa.getBuyPrice(wearablesSubject, 1 ether);
        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 1 ether);
        uint256 protocolFeePercent = proxySofa.protocolFeePercent();
        uint256 creatorFeePercent = proxySofa.creatorFeePercent();
        vm.expectEmit(true, true, true, true);
        emit Trade(
            user1,
            wearablesSubject,
            true,
            true,
            1 ether,
            buyPrice,
            (buyPrice * protocolFeePercent) / 1 ether,
            (buyPrice * creatorFeePercent) / 1 ether,
            1 ether
        );
        // buy 1 full share of the wearable
        proxySofa.buyWearables{value: buyPriceAfterFee}(wearablesSubject, 1 ether);
        assertEq(user1.balance, 1 ether - buyPriceAfterFee);
    }

    function testExcessivePayments() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        assertEq(user1.balance, 1 ether);
        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 1 ether);
        vm.expectRevert(bytes4(keccak256("ExcessivePayment()")));
        // buy 1 full share of the wearable with excessive payment
        proxySofa.buyWearables{value: buyPriceAfterFee + 0.1 ether}(wearablesSubject, 1 ether);
    }

    function testBuyPrivateWearablesFailed() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PRIVATE
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: false,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        assertEq(user1.balance, 1 ether);
        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 1 ether);
        vm.expectRevert(bytes4(keccak256("InvalidSaleState()")));
        proxySofa.buyWearables{value: buyPriceAfterFee}(wearablesSubject, 1 ether);
    }

    function testBuyPrivateWearables() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));
        {
            vm.startPrank(signer1);
            bytes32 digest = keccak256(
                abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
            ).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
            bytes memory signature = abi.encodePacked(r, s, v);
            vm.stopPrank();

            vm.startPrank(creator1);
            vm.expectEmit(true, true, true, true);
            emit WearableCreated(
                creator1,
                wearablesSubject,
                "test hoodie",
                "hoodie",
                "this is a test hoodie",
                "hoodie image url",
                50000,
                SofamonWearables.SaleStates.PRIVATE
            );
            proxySofa.createWearable(
                SofamonWearables.CreateWearableParams({
                    name: "test hoodie",
                    category: "hoodie",
                    description: "this is a test hoodie",
                    imageURI: "hoodie image url",
                    isPublic: false,
                    curveAdjustmentFactor: 50000,
                    signature: signature
                })
            );
            vm.stopPrank();
        }

        {
            uint256 nonce = proxySofa.nonces(user1);
            vm.startPrank(signer1);
            bytes32 digest2 = keccak256(abi.encodePacked(user1, "buy", wearablesSubject, uint256(1 ether), nonce))
                .toEthSignedMessageHash();
            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signer1Privatekey, digest2);
            bytes memory signature2 = abi.encodePacked(r2, s2, v2);
            vm.stopPrank();

            vm.startPrank(user1);
            vm.deal(user1, 1 ether);
            assertEq(user1.balance, 1 ether);
            uint256 buyPrice = proxySofa.getBuyPrice(wearablesSubject, 1 ether);
            uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 1 ether);
            uint256 protocolFeePercent = proxySofa.protocolFeePercent();
            uint256 creatorFeePercent = proxySofa.creatorFeePercent();
            vm.expectEmit(true, true, true, true);
            emit NonceUpdated(user1, 1);
            vm.expectEmit(true, true, true, true);
            emit Trade(
                user1,
                wearablesSubject,
                true,
                false,
                1 ether,
                buyPrice,
                (buyPrice * protocolFeePercent) / 1 ether,
                (buyPrice * creatorFeePercent) / 1 ether,
                1 ether
            );
            // buy 1 full share of the wearable
            proxySofa.buyPrivateWearables{value: buyPriceAfterFee}(wearablesSubject, 1 ether, signature2);
            assertEq(user1.balance, 1 ether - buyPriceAfterFee);
        }
    }

    function testSellWearables() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PUBLIC
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        assertEq(user1.balance, 1 ether);
        // get price for 2 full share of the wearable
        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 2 ether);
        proxySofa.buyWearables{value: buyPriceAfterFee}(wearablesSubject, 2 ether);
        assertEq(user1.balance, 1 ether - buyPriceAfterFee);
        assertEq(proxySofa.wearablesBalance(wearablesSubject, user1), 2 ether);

        uint256 sellPrice = proxySofa.getSellPrice(wearablesSubject, 1 ether);
        uint256 sellPriceAfterFee = proxySofa.getSellPriceAfterFee(wearablesSubject, 1 ether);
        uint256 protocolFeePercent = proxySofa.protocolFeePercent();
        uint256 creatorFeePercent = proxySofa.creatorFeePercent();
        vm.expectEmit(true, true, true, true);
        emit Trade(
            user1,
            wearablesSubject,
            false,
            true,
            1 ether,
            sellPrice,
            (sellPrice * protocolFeePercent) / 1 ether,
            (sellPrice * creatorFeePercent) / 1 ether,
            1 ether
        );
        proxySofa.sellWearables(wearablesSubject, 1 ether);
        assertEq(user1.balance, 1 ether - buyPriceAfterFee + sellPriceAfterFee);
        assertEq(proxySofa.wearablesBalance(wearablesSubject, user1), 1 ether);
    }

    function testSellPrivateWearables() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));
        {
            vm.startPrank(signer1);
            bytes32 digest = keccak256(
                abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
            ).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
            bytes memory signature = abi.encodePacked(r, s, v);
            vm.stopPrank();

            vm.startPrank(creator1);
            vm.expectEmit(true, true, true, true);
            emit WearableCreated(
                creator1,
                wearablesSubject,
                "test hoodie",
                "hoodie",
                "this is a test hoodie",
                "hoodie image url",
                50000,
                SofamonWearables.SaleStates.PRIVATE
            );
            proxySofa.createWearable(
                SofamonWearables.CreateWearableParams({
                    name: "test hoodie",
                    category: "hoodie",
                    description: "this is a test hoodie",
                    imageURI: "hoodie image url",
                    isPublic: false,
                    curveAdjustmentFactor: 50000,
                    signature: signature
                })
            );
            vm.stopPrank();
        }

        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 2 ether);

        {
            uint256 nonce1 = proxySofa.nonces(user1);
            vm.startPrank(signer1);
            bytes32 digest2 = keccak256(abi.encodePacked(user1, "buy", wearablesSubject, uint256(2 ether), nonce1))
                .toEthSignedMessageHash();
            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signer1Privatekey, digest2);
            bytes memory signature2 = abi.encodePacked(r2, s2, v2);
            vm.stopPrank();

            vm.startPrank(user1);
            vm.deal(user1, 1 ether);
            assertEq(user1.balance, 1 ether);
            // get price for 2 full share of the wearable
            proxySofa.buyPrivateWearables{value: buyPriceAfterFee}(wearablesSubject, 2 ether, signature2);
            assertEq(user1.balance, 1 ether - buyPriceAfterFee);
            assertEq(proxySofa.wearablesBalance(wearablesSubject, user1), 2 ether);
            vm.stopPrank();
        }

        {
            uint256 nonce2 = proxySofa.nonces(user1);
            vm.startPrank(signer1);
            bytes32 digest3 = keccak256(abi.encodePacked(user1, "sell", wearablesSubject, uint256(1 ether), nonce2))
                .toEthSignedMessageHash();
            (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(signer1Privatekey, digest3);
            bytes memory signature3 = abi.encodePacked(r3, s3, v3);
            vm.stopPrank();

            vm.startPrank(user1);
            uint256 sellPrice = proxySofa.getSellPrice(wearablesSubject, 1 ether);
            uint256 sellPriceAfterFee = proxySofa.getSellPriceAfterFee(wearablesSubject, 1 ether);
            uint256 protocolFeePercent = proxySofa.protocolFeePercent();
            uint256 creatorFeePercent = proxySofa.creatorFeePercent();
            vm.expectEmit(true, true, true, true);
            emit NonceUpdated(user1, 2);
            vm.expectEmit(true, true, true, true);
            emit Trade(
                user1,
                wearablesSubject,
                false,
                false,
                1 ether,
                sellPrice,
                (sellPrice * protocolFeePercent) / 1 ether,
                (sellPrice * creatorFeePercent) / 1 ether,
                1 ether
            );
            proxySofa.sellPrivateWearables(wearablesSubject, 1 ether, signature3);
            assertEq(user1.balance, 1 ether - buyPriceAfterFee + sellPriceAfterFee);
            assertEq(proxySofa.wearablesBalance(wearablesSubject, user1), 1 ether);
            vm.stopPrank();
        }
    }

    function testSellAllWearables() public {
        // Setup wearable
        // ------------------------------------------------------------
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50_000,
                signature: signature
            })
        );
        vm.stopPrank();
        // ------------------------------------------------------------

        vm.startPrank(creator1);
        vm.deal(creator1, 1_000_000 ether);

        uint256 total = 0;
        // buy 10 batches of wearables
        for (uint256 i; i < 10; i++) {
            uint256 amount = 1e18;
            total += amount;
            uint256 buyPrice = proxySofa.getBuyPriceAfterFee(wearablesSubject, amount);
            proxySofa.buyWearables{value: buyPrice}(wearablesSubject, amount);
        }

        console.log("sellPrice                ", proxySofa.getSellPrice(wearablesSubject, total));
        console.log("SofamonWearables balance:", address(proxySofa).balance);

        // Sell all wearables
        proxySofa.sellWearables(wearablesSubject, total);

        console.log(creator1.balance);
    }

    function testTransferWearables() public {
        bytes32 wearablesSubject = keccak256(abi.encode("test hoodie", "hoodie image url"));

        vm.startPrank(signer1);
        bytes32 digest = keccak256(
            abi.encode(creator1, "test hoodie", "hoodie", "this is a test hoodie", "hoodie image url")
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer1Privatekey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(creator1);
        vm.expectEmit(true, true, true, true);
        emit WearableCreated(
            creator1,
            wearablesSubject,
            "test hoodie",
            "hoodie",
            "this is a test hoodie",
            "hoodie image url",
            50000,
            SofamonWearables.SaleStates.PUBLIC
        );
        proxySofa.createWearable(
            SofamonWearables.CreateWearableParams({
                name: "test hoodie",
                category: "hoodie",
                description: "this is a test hoodie",
                imageURI: "hoodie image url",
                isPublic: true,
                curveAdjustmentFactor: 50000,
                signature: signature
            })
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        assertEq(user1.balance, 1 ether);
        // get price for 3 full share of the wearable
        uint256 buyPriceAfterFee = proxySofa.getBuyPriceAfterFee(wearablesSubject, 3 ether);
        proxySofa.buyWearables{value: buyPriceAfterFee}(wearablesSubject, 3 ether);
        assertEq(user1.balance, 1 ether - buyPriceAfterFee);

        // transfer 1 full share of the wearable to user2
        vm.expectEmit(true, true, true, true);
        emit WearableTransferred(user1, user2, wearablesSubject, 1 ether);
        proxySofa.transferWearables(wearablesSubject, user1, user2, 1 ether);
        assertEq(proxySofa.wearablesBalance(wearablesSubject, user1), 2 ether);
        assertEq(proxySofa.wearablesBalance(wearablesSubject, user2), 1 ether);
    }
}
