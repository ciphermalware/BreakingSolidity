// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title VulnerableNFTMarketplace
 * @dev A marketplace contract that allows users to create offers for specific NFTs
 *      using Merkle tree criteria. Contains a critical vulnerability in Merkle tree
 *      leaf handling that allows unintended tokenIds to fulfill offers.
 * @notice This contract is vulnerable and should not be used in production
 */
contract VulnerableNFTMarketplace is ReentrancyGuard, Ownable {
    using MerkleProof for bytes32[];

    // Marketplace fee (2.5%)
    uint256 public constant MARKETPLACE_FEE = 250;
    uint256 public constant FEE_DENOMINATOR = 10000;

    struct Offer {
        address offerer;           // User who created the offer
        address nftContract;       // NFT contract address
        address paymentToken;      // ERC20 token for payment 
        uint256 price;             // Price per NFT
        bytes32 merkleRoot;        // Root of Merkle tree containing acceptable tokenIds
        uint256 expiration;        // Offer expiration timestamp
        bool isActive;             // Whether the offer is still active
        uint256 maxFulfillments;   // Maximum number of times this offer can be fulfilled
        uint256 currentFulfillments; // Current number of fulfillments
    }

    // Mapping from offer ID to offer details
    mapping(uint256 => Offer) public offers;
    
    // Counter for offer IDs
    uint256 public nextOfferId;
    
    // Mapping to track if an offer has been fulfilled for a specific tokenId
    mapping(uint256 => mapping(uint256 => bool)) public offerTokenFulfilled;

    event OfferCreated(
        uint256 indexed offerId,
        address indexed offerer,
        address indexed nftContract,
        bytes32 merkleRoot,
        uint256 price,
        uint256 expiration
    );

    event OfferFulfilled(
        uint256 indexed offerId,
        address indexed fulfiller,
        uint256 indexed tokenId,
        uint256 price
    );

    event OfferCancelled(uint256 indexed offerId);

    constructor() {}

    /**
     * @dev Creates a new offer for NFTs matching the Merkle tree criteria
     * @param nftContract Address of the NFT contract
     * @param paymentToken Address of the payment token (address(0) for ETH)
     * @param price Price per NFT
     * @param merkleRoot Root of Merkle tree containing acceptable tokenIds
     * @param expiration Offer expiration timestamp
     * @param maxFulfillments Maximum number of times this offer can be fulfilled
     */
    function createOffer(
        address nftContract,
        address paymentToken,
        uint256 price,
        bytes32 merkleRoot,
        uint256 expiration,
        uint256 maxFulfillments
    ) external payable nonReentrant {
        require(nftContract != address(0), "Invalid NFT contract");
        require(price > 0, "Price must be greater than 0");
        require(expiration > block.timestamp, "Expiration must be in the future");
        require(maxFulfillments > 0, "Max fulfillments must be greater than 0");
        require(merkleRoot != bytes32(0), "Invalid Merkle root");

        uint256 offerId = nextOfferId++;

        offers[offerId] = Offer({
            offerer: msg.sender,
            nftContract: nftContract,
            paymentToken: paymentToken,
            price: price,
            merkleRoot: merkleRoot,
            expiration: expiration,
            isActive: true,
            maxFulfillments: maxFulfillments,
            currentFulfillments: 0
        });

        // If paying with ETH, escrow the payment
        if (paymentToken == address(0)) {
            require(msg.value == price * maxFulfillments, "Incorrect ETH amount");
        } else {
            // Transfer ERC20 tokens to this contract for escrow
            require(
                IERC20(paymentToken).transferFrom(msg.sender, address(this), price * maxFulfillments),
                "Token transfer failed"
            );
        }

        emit OfferCreated(offerId, msg.sender, nftContract, merkleRoot, price, expiration);
    }

    /**
     * @dev Fulfills an offer by providing an NFT that matches the Merkle tree criteria
     * @param offerId ID of the offer to fulfill
     * @param tokenId ID of the NFT token to trade
     * @param merkleProof Merkle proof that the tokenId is in the acceptable set
     * 
     * @notice VULNERABILITY: This function uses tokenId directly as a leaf in the Merkle tree
     *         verification, which allows intermediate hash values to be used as valid tokenIds.
     *         An attacker can exploit this by using a tokenId that equals any intermediate
     *         hash in the Merkle tree, bypassing the intended restrictions.
     */
    function fulfillOffer(
        uint256 offerId,
        uint256 tokenId,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        Offer storage offer = offers[offerId];
        
        require(offer.isActive, "Offer is not active");
        require(block.timestamp <= offer.expiration, "Offer has expired");
        require(offer.currentFulfillments < offer.maxFulfillments, "Offer fully fulfilled");
        require(!offerTokenFulfilled[offerId][tokenId], "TokenId already used for this offer");

        // VULNERABLE CODE: Using tokenId directly as leaf instead of hashing it
        // This allows intermediate hash values to be used as valid tokenIds
        bytes32 leaf = bytes32(tokenId);
        
        require(
            _verifyMerkleProof(merkleProof, offer.merkleRoot, leaf),
            "Invalid Merkle proof"
        );

        // Verify that the sender owns the NFT
        IERC721 nft = IERC721(offer.nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner of NFT");
        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId) == address(this), "Marketplace not approved");

        // Mark this tokenId as used for this offer
        offerTokenFulfilled[offerId][tokenId] = true;
        offer.currentFulfillments++;

        // Calculate marketplace fee
        uint256 marketplaceFee = (offer.price * MARKETPLACE_FEE) / FEE_DENOMINATOR;
        uint256 sellerAmount = offer.price - marketplaceFee;

        // Transfer NFT from seller to buyer
        nft.transferFrom(msg.sender, offer.offerer, tokenId);

        // Handle payment
        if (offer.paymentToken == address(0)) {
            // ETH payment
            payable(msg.sender).transfer(sellerAmount);
            payable(owner()).transfer(marketplaceFee);
        } else {
            // ERC20 payment
            IERC20 token = IERC20(offer.paymentToken);
            require(token.transfer(msg.sender, sellerAmount), "Payment to seller failed");
            require(token.transfer(owner(), marketplaceFee), "Fee payment failed");
        }

        emit OfferFulfilled(offerId, msg.sender, tokenId, offer.price);

        // Deactivate offer if fully fulfilled
        if (offer.currentFulfillments >= offer.maxFulfillments) {
            offer.isActive = false;
        }
    }

    /**
     * @dev Cancels an active offer and refunds remaining payments
     * @param offerId ID of the offer to cancel
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.offerer == msg.sender, "Not the offerer");
        require(offer.isActive, "Offer is not active");

        offer.isActive = false;

        // Calculate refund amount
        uint256 remainingFulfillments = offer.maxFulfillments - offer.currentFulfillments;
        uint256 refundAmount = offer.price * remainingFulfillments;

        if (refundAmount > 0) {
            if (offer.paymentToken == address(0)) {
                payable(msg.sender).transfer(refundAmount);
            } else {
                require(
                    IERC20(offer.paymentToken).transfer(msg.sender, refundAmount),
                    "Refund failed"
                );
            }
        }

        emit OfferCancelled(offerId);
    }

    /**
     * @dev Internal function to verify Merkle proof
     * @param proof Merkle proof array
     * @param root Merkle root
     * @param leaf Leaf to verify
     * @return bool Whether the proof is valid
     * 
     * @notice This is the vulnerable function - it doesn't hash the leaf,
     *         allowing intermediate hash values to be used as valid leaves
     */
    function _verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf; // VULNERABILITY: Not hashing the leaf!
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }

    /**
     * @dev View function to get offer details
     * @param offerId ID of the offer
     * @return Offer struct containing all offer details
     */
    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    /**
     * @dev Emergency function to withdraw stuck funds (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Emergency function to withdraw stuck ERC20 tokens (owner only)
     * @param token Address of the ERC20 token to withdraw
     */
    function emergencyWithdrawToken(address token) external onlyOwner {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
