// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IBlast} from "./IBlast.sol";

// Errors
error InvalidSignature();
error InsufficientBaseUnit();
error WearableAlreadyCreated();
error WearableNotCreated();
error InsufficientPayment();
error SendFundsFailed();
error LastWearableCannotBeSold();
error InsufficientHoldings();
error TransferToZeroAddress();
error IncorrectSender();

/**
 * @title SofamonWearables
 * @author lixingyu.eth <@0xlxy>
 */
contract SofamonWearables is Ownable2Step {
    using ECDSA for bytes32;

    // 3% creator fee
    uint256 private constant CREATOR_FEE_PERCENT = 0.03 ether;

    // 3% protocol fee
    uint256 private constant PROTOCOL_FEE_PERCENT = 0.03 ether;

    // Base unit of a wearable. 1000 fractional shares = 1 full wearable
    uint256 private constant BASE_WEARABLE_UNIT = 0.001 ether;

    // Address of the protocol fee destination
    address public protocolFeeDestination;

    // Percentage of the protocol fee
    uint256 public protocolFeePercent;

    // Percentage of the creator fee
    uint256 public creatorFeePercent;

    // Address that signs messages used for creating wearables
    address public createSigner;

    // Blast interface
    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

    event ProtocolFeeDestinationUpdated(address feeDestination);

    event ProtocolFeePercentUpdated(uint256 feePercent);

    event CreatorFeePercentUpdated(uint256 feePercent);

    event CreateSignerUpdated(address signer);

    event WearableCreated(
        address creator, bytes32 subject, string name, string category, string description, string imageURI
    );

    event Trade(
        address trader,
        bytes32 subject,
        bool isBuy,
        uint256 wearableAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 creatorEthAmount,
        uint256 supply
    );

    event WearableTransferred(address from, address to, bytes32 subject, uint256 amount);

    struct Wearable {
        address creator;
        string name;
        string category;
        string description;
        string imageURI;
    }

    // wearablesSubject => Wearable
    mapping(bytes32 => Wearable) public wearables;

    // wearablesSubject => (Holder => Balance)
    mapping(bytes32 => mapping(address => uint256)) public wearablesBalance;

    // wearablesSubject => Supply
    mapping(bytes32 => uint256) public wearablesSupply;

    constructor(address _governor, address _signer) Ownable() {
        // Configure protocol settings
        protocolFeePercent = PROTOCOL_FEE_PERCENT;
        creatorFeePercent = CREATOR_FEE_PERCENT;
        createSigner = _signer;

        // Configure Blast automatic yield
        BLAST.configureAutomaticYield();

        // Configure Blast claimable gas fee
        BLAST.configureClaimableGas();

        // Configure Blast governor
        BLAST.configureGovernor(_governor);
    }

    // =========================================================================
    //                          Protocol Settings
    // =========================================================================

    /// @dev Sets the protocol fee destination.
    /// Emits a {ProtocolFeeDestinationUpdated} event.
    function setProtocolFeeDestination(address _feeDestination) external onlyOwner {
        protocolFeeDestination = _feeDestination;
        emit ProtocolFeeDestinationUpdated(_feeDestination);
    }

    /// @dev Sets the protocol fee percentage.
    /// Emits a {ProtocolFeePercentUpdated} event.
    function setProtocolFeePercent(uint256 _feePercent) external onlyOwner {
        protocolFeePercent = _feePercent;
        emit ProtocolFeePercentUpdated(_feePercent);
    }

    /// @dev Sets the creator fee percentage.
    /// Emits a {CreatorFeePercentUpdated} event.
    function setCreatorFeePercent(uint256 _feePercent) external onlyOwner {
        creatorFeePercent = _feePercent;
        emit CreatorFeePercentUpdated(_feePercent);
    }

    /// @dev Sets the address that signs messages used for creating wearables.
    /// Emits a {CreateSignerUpdated} event.
    function setCreateSigner(address _signer) external onlyOwner {
        createSigner = _signer;
        emit CreateSignerUpdated(_signer);
    }

    // =========================================================================
    //                          Create Wearable Logic
    // =========================================================================

    /// @dev Creates a sofamon wearable. invite-code needed.
    /// Emits a {WearableCreated} event.
    function createWearable(
        string calldata name,
        string calldata category,
        string calldata description,
        string calldata imageURI,
        bytes calldata signature
    ) external {
        // Validate signature
        {
            bytes32 hashVal = keccak256(abi.encodePacked(msg.sender, name, category, description, imageURI));
            bytes32 signedHash = hashVal.toEthSignedMessageHash();
            if (signedHash.recover(signature) != createSigner) {
                revert InvalidSignature();
            }
        }

        // Generate wearable subject
        bytes32 wearablesSubject = keccak256(abi.encode(name, imageURI));

        // Check if wearable already exists
        uint256 supply = wearablesSupply[wearablesSubject];
        if (supply != 0) revert WearableAlreadyCreated();

        // Update wearables mapping
        wearables[wearablesSubject] = Wearable(msg.sender, name, category, description, imageURI);

        emit WearableCreated(msg.sender, wearablesSubject, name, category, description, imageURI);
    }

    // =========================================================================
    //                          Trade Wearable Logic
    // =========================================================================
    /// @dev Returns the curve of `x`
    function _curve(uint256 x) private pure returns (uint256) {
        return x * x * x;
    }

    /// @dev Returns the price based on `supply` and `amount`
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        return (_curve(supply + amount) - _curve(supply)) / 1 ether / 1 ether / 50_000;
    }

    /// @dev Returns the buy price of `amount` of `wearablesSubject`.
    function getBuyPrice(bytes32 wearablesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(wearablesSupply[wearablesSubject], amount);
    }

    /// @dev Returns the sell price of `amount` of `wearablesSubject`.
    function getSellPrice(bytes32 wearablesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(wearablesSupply[wearablesSubject] - amount, amount);
    }

    /// @dev Returns the buy price of `amount` of `wearablesSubject` after fee.
    function getBuyPriceAfterFee(bytes32 wearablesSubject, uint256 amount) external view returns (uint256) {
        // Get buy price before fee
        uint256 price = getBuyPrice(wearablesSubject, amount);

        // Get protocol fee
        uint256 protocolFee = _getProtocolFee(price);

        // Get creator fee
        uint256 creatorFee = _getCreatorFee(price);

        // Get final buy price
        return price + protocolFee + creatorFee;
    }

    /// @dev Returns the sell price of `amount` of `wearablesSubject` after fee.
    function getSellPriceAfterFee(bytes32 wearablesSubject, uint256 amount) external view returns (uint256) {
        // Get sell price before fee
        uint256 price = getSellPrice(wearablesSubject, amount);

        // Get protocol fee
        uint256 protocolFee = _getProtocolFee(price);

        // Get creator fee
        uint256 creatorFee = _getCreatorFee(price);

        // Get final sell price
        return price - protocolFee - creatorFee;
    }

    /// @dev Returns the protocol fee.
    function _getProtocolFee(uint256 price) internal view returns (uint256) {
        return (price * protocolFeePercent) / 1 ether;
    }

    /// @dev Returns the creator fee.
    function _getCreatorFee(uint256 price) internal view returns (uint256) {
        return (price * creatorFeePercent) / 1 ether;
    }

    /// @dev Buys `amount` of `wearablesSubject`.
    /// Emits a {Trade} event.
    function buyWearables(bytes32 wearablesSubject, uint256 amount) external payable {
        // Check if amount is greater than base unit
        if (amount < BASE_WEARABLE_UNIT) revert InsufficientBaseUnit();

        // Check if wearable exists
        if (wearables[wearablesSubject].creator == address(0)) revert WearableNotCreated();

        uint256 supply = wearablesSupply[wearablesSubject];

        // Get buy price before fee
        uint256 price = getPrice(supply, amount);

        // Get protocol fee
        uint256 protocolFee = _getProtocolFee(price);

        // Get creator fee
        uint256 creatorFee = _getCreatorFee(price);

        // Check if user has enough funds
        if (msg.value < price + protocolFee + creatorFee) {
            revert InsufficientPayment();
        }

        // Update wearables balance and supply
        wearablesBalance[wearablesSubject][msg.sender] = wearablesBalance[wearablesSubject][msg.sender] + amount;
        wearablesSupply[wearablesSubject] = supply + amount;

        // Get creator fee destination
        address creatorFeeDestination = wearables[wearablesSubject].creator;

        emit Trade(msg.sender, wearablesSubject, true, amount, price, protocolFee, creatorFee, supply + amount);

        // Send protocol fee to protocol fee destination
        (bool success1,) = protocolFeeDestination.call{value: protocolFee}("");

        //Send creator fee to creator fee destination
        (bool success2,) = creatorFeeDestination.call{value: creatorFee}("");

        // Check if all funds were sent successfully
        if (!(success1 && success2)) revert SendFundsFailed();
    }

    /// @dev Sells `amount` of `wearablesSubject`.
    /// Emits a {Trade} event.
    function sellWearables(bytes32 wearablesSubject, uint256 amount) external payable {
        // Check if amount is greater than base unit
        if (amount < BASE_WEARABLE_UNIT) revert InsufficientBaseUnit();

        // Check if wearable exists
        uint256 supply = wearablesSupply[wearablesSubject];
        if (supply <= amount) revert LastWearableCannotBeSold();

        // Get sell price before fee
        uint256 price = getPrice(supply - amount, amount);

        // Get protocol fee
        uint256 protocolFee = _getProtocolFee(price);

        // Get creator fee
        uint256 creatorFee = _getCreatorFee(price);

        // Check if user has enough amount for sale
        if (wearablesBalance[wearablesSubject][msg.sender] < amount) {
            revert InsufficientHoldings();
        }

        // Update wearables balance and supply
        wearablesBalance[wearablesSubject][msg.sender] = wearablesBalance[wearablesSubject][msg.sender] - amount;
        wearablesSupply[wearablesSubject] = supply - amount;

        // Get creator fee destination
        address creatorFeeDestination = wearables[wearablesSubject].creator;

        emit Trade(msg.sender, wearablesSubject, false, amount, price, protocolFee, creatorFee, supply - amount);

        // Send sell funds to seller
        (bool success1,) = msg.sender.call{value: price - protocolFee - creatorFee}("");

        // Send protocol fee to protocol fee destination
        (bool success2,) = protocolFeeDestination.call{value: protocolFee}("");

        // Send creator fee to creator fee destination
        (bool success3,) = creatorFeeDestination.call{value: creatorFee}("");

        // Check if all funds were sent successfully
        if (!(success1 && success2 && success3)) revert SendFundsFailed();
    }

    /// @dev Transfers `amount` of `wearablesSubject` from `from` to `to`.
    /// Emits a {WearableTransferred} event.
    function transferWearables(bytes32 wearablesSubject, address from, address to, uint256 amount) external {
        // Check if to address is non-zero
        if (to == address(0)) revert TransferToZeroAddress();

        // Check if amount is greater than base unit
        if (amount < BASE_WEARABLE_UNIT) revert InsufficientBaseUnit();

        // Check if message sender is the from address
        if (_msgSender() != from) revert IncorrectSender();

        // Check if user has enough wearables for transfer
        if (wearablesBalance[wearablesSubject][from] < amount) {
            revert InsufficientHoldings();
        }

        // Update wearables balance and supply
        wearablesBalance[wearablesSubject][from] = wearablesBalance[wearablesSubject][from] - amount;
        wearablesBalance[wearablesSubject][to] = wearablesBalance[wearablesSubject][to] + amount;

        emit WearableTransferred(from, to, wearablesSubject, amount);
    }

    // =========================================================================
    //                          Blast Gas Claim
    // =========================================================================
    /// @dev Claim all gas
    function claimAllGas(address recipientOfGas) external {
        BLAST.claimAllGas(address(this), recipientOfGas);
    }

    /// @dev Claims gas with 100% claim rate
    function claimMaxGas(address recipientOfGas) external {
        BLAST.claimMaxGas(address(this), recipientOfGas);
    }

    /// @dev Claims gas with custom claim rate
    function claimGasAtMinClaimRate(address recipientOfGas, uint256 minClaimRateBips) external {
        BLAST.claimGasAtMinClaimRate(address(this), recipientOfGas, minClaimRateBips);
    }

    // =========================================================================
    //                          Blast Read Config
    // =========================================================================
    /// @dev Returns the claimable yield of this smart contract
    function readClaimableYield() public view {
        BLAST.readClaimableYield(address(this));
    }

    /// @dev Returns the yield configuration of this smart contract
    function readYieldConfiguration() public view {
        BLAST.readYieldConfiguration(address(this));
    }

    /// @dev Returns the gas params of this smart contract
    function readGasParams() public view {
        BLAST.readGasParams(address(this));
    }
}
