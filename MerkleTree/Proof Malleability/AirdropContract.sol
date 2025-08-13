// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AirdropContract
 * @dev An airdrop contract that uses Merkle trees for claim validation
 *      Contains a critical signature malleability vulnerability where
 *      multiple valid proofs can be generated for the same leaf which allows
 *      users to claim airdrops multiple times
 * 
 */
contract VulnerableAirdropContract is ReentrancyGuard, Ownable {
    
    // The ERC20 token being distributed
    IERC20 public immutable token;
    
    // Merkle root for the airdrop eligibility
    bytes32 public merkleRoot;
    
    // Amount of tokens each eligible address can claim
    uint256 public claimAmount;
    
    // Track used proofs to prevent replay attacks (VULNERABLE APPROACH)
    mapping(bytes32 => bool) public usedProofs;
    
    // Track claimed addresses (intended protection but bypassable due to malleability)
    mapping(address => bool) public hasClaimed;
    
    // Airdrop active flag
    bool public airdropActive;
    
    event AirdropClaimed(address indexed claimer, uint256 amount, bytes32 proofHash);
    event AirdropConfigured(bytes32 merkleRoot, uint256 claimAmount);
    
    constructor(address _token) {
        token = IERC20(_token);
    }
    
    /**
     * @dev Configures the airdrop with Merkle root and claim amount
     * @param _merkleRoot Root of the Merkle tree containing eligible addresses
     * @param _claimAmount Amount of tokens each address can claim
     */
    function configureAirdrop(bytes32 _merkleRoot, uint256 _claimAmount) external onlyOwner {
        merkleRoot = _merkleRoot;
        claimAmount = _claimAmount;
        airdropActive = true;
        
        emit AirdropConfigured(_merkleRoot, _claimAmount);
    }
    
    /**
     * @dev Claims airdrop tokens using Merkle proof validation
     * @param merkleProof Array of hashes forming the Merkle proof
     * 
     * @notice This function is vulnerable to signature malleability
     *         because it doesn't enforce canonical proof ordering. Multiple valid
     *         proofs can be generated for the same leaf which allows the bypass of replay protection
     */
    function claimAirdrop(bytes32[] calldata merkleProof) external nonReentrant {
        require(airdropActive, "Airdrop is not active");
        require(!hasClaimed[msg.sender], "Address has already claimed");
        
        // Create leaf from sender's address
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        
        // Verify the Merkle proof (VULNERABLE IMPLEMENTATION)
        require(_verifyMerkleProof(merkleProof, merkleRoot, leaf), "Invalid Merkle proof");
        
        // Calculate proof hash for replay protection (VULNERABLE)
        bytes32 proofHash = keccak256(abi.encodePacked(merkleProof));
        require(!usedProofs[proofHash], "Proof already used");
        
        // Mark proof as used and address as claimed
        usedProofs[proofHash] = true;
        hasClaimed[msg.sender] = true;
        
        // Transfer tokens to claimer
        require(token.transfer(msg.sender, claimAmount), "Token transfer failed");
        
        emit AirdropClaimed(msg.sender, claimAmount, proofHash);
    }
    
    /**
     * @dev Internal function to verify Merkle proof
     * @param proof Merkle proof array
     * @param root Merkle root
     * @param leaf Leaf to verify
     * @return bool Whether the proof is valid
     * 
     * @notice This implementation doesn't enforce canonical ordering
     *         of proof elements which allows for proof malleability. The same leaf can
     *         be proven using different orderings of the same proof elements.
     */
    function _verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            // VULNERABLE: This ordering logic allows malleability
            // Different orderings of the same elements can produce valid proofs
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
    
    function _verifyMerkleProofAlternative(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            // VULNERABLE: Random ordering allows many valid proofs
            // This allows arbitrary reordering of proof elements
            computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
        }
        
        return computedHash == root;
    }
    
    /**
     * @dev Emergency function to pause the airdrop
     */
    function pauseAirdrop() external onlyOwner {
        airdropActive = false;
    }
    
    /**
     * @dev Emergency function to withdraw remaining tokens
     */
    function withdrawTokens() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(owner(), balance), "Withdrawal failed");
    }
    
    /**
     * @dev View function to check if a proof has been used
     * @param merkleProof The proof to check
     * @return bool Whether the proof has been used
     */
    function isProofUsed(bytes32[] calldata merkleProof) external view returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(merkleProof));
        return usedProofs[proofHash];
    }
    
    /**
     * @dev View function to get the hash of a proof
     * @param merkleProof The proof to hash
     * @return bytes32 The hash of the proof
     */
    function getProofHash(bytes32[] calldata merkleProof) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(merkleProof));
    }
}

/**
 * @title MockToken
 * @dev Simple ERC20 token for testing the airdrop
 */
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000000 * 10**18); // 1M tokens
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
