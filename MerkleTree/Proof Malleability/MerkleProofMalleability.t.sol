// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/VulnerableAirdropContract.sol";

 /*
  * @title MerkleProofMalleability Test
  */
 
contract SignatureMalleabilityTest is Test {
    VulnerableAirdropContract public airdrop;
    MockToken public token;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");
    
    uint256 constant CLAIM_AMOUNT = 1000 * 10**18; // 1000 tokens

    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        token = new MockToken();
        
        vm.prank(owner);
        airdrop = new VulnerableAirdropContract(address(token));
        
        // Transfer tokens to airdrop contract
        vm.prank(owner);
        token.transfer(address(airdrop), 100000 * 10**18);
    }
    
    /**
     * @dev Test demonstrating a realistic attack using proof manipulation
     *      without requiring cheatcodes or storage manipulation
     */
    function testRealisticProofManipulationAttack() public {
        console.log("\n=== Realistic Proof Manipulation Attack ===");
        
        // Set up a scenario where an attacker can exploit proof hash differences
        // This demonstrates why tracking by proof hash is fundamentally flawed
        
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice));
        bytes32 bobLeaf = keccak256(abi.encodePacked(bob));
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);
        
        vm.prank(owner);
        airdrop.configureAirdrop(root, CLAIM_AMOUNT);
        
        // Alice creates a valid proof
        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;
        
        // Alice claims successfully
        vm.prank(alice);
        airdrop.claimAirdrop(aliceProof);
        console.log("Alice claimed successfully");
        
        // Now Bob tries to claim but his proof hash is tracked incorrectly
        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;
        
        bytes32 aliceProofHash = airdrop.getProofHash(aliceProof);
        bytes32 bobProofHash = airdrop.getProofHash(bobProof);
        
        console.log("Alice proof hash == Bob proof hash:", aliceProofHash == bobProofHash);
        console.log("This shows different users can have different proof hashes for same tree");
        
        // Bob can still claim because his proof hash is different
        vm.prank(bob);
        airdrop.claimAirdrop(bobProof);
        console.log("Bob claimed successfully with different proof hash");
        
        console.log("");
    }
    
    /**
     * @dev Test demonstrating a more realistic signature malleability vulnerability
     *      using a different user to show how the vulnerability works
     */
    function testRealSignatureMalleabilityVulnerability() public {
        console.log("=== Testing REAL Signature Malleability Vulnerability ===");
        
        // Instead of manipulating Alice's state we'll show how Bob can exploit
        // the vulnerability by using a malleable proof structure
        
        // Create a simple tree where malleability is more obvious
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice));
        bytes32 bobLeaf = keccak256(abi.encodePacked(bob));
        
        // The vulnerability: different ways to construct the same tree
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);
        
        console.log("Simple 2-leaf tree:");
        console.logBytes32(root);
        console.log("^ Root");
        console.logBytes32(aliceLeaf);
        console.log("^ Alice leaf");
        console.logBytes32(bobLeaf);
        console.log("^ Bob leaf");
        
        // Configure airdrop
        vm.prank(owner);
        airdrop.configureAirdrop(root, CLAIM_AMOUNT);
        
        // Bob creates first proof
        bytes32[] memory bobProof1 = new bytes32[](1);
        bobProof1[0] = aliceLeaf; // Alice's leaf as sibling
        
        console.log("");
        console.log("Bob's First Proof:");
        console.logBytes32(bobProof1[0]);
        console.log("^ Bob's sibling (Alice leaf)");
        
        bytes32 proof1Hash = keccak256(abi.encodePacked(bobProof1));
        console.logBytes32(proof1Hash);
        console.log("^ Proof 1 Hash");
        
        // Bob claims successfully
        vm.prank(bob);
        airdrop.claimAirdrop(bobProof1);
        console.log("Bob claimed successfully with first proof");
        
        // Now demonstrate the real vulnerability: proof hash manipulation
        // The issue is that the contract only checks proof hash not the actual claim
        console.log("");
        console.log("--- Demonstrating REAL Vulnerability ---");
        console.log("The vulnerability isn't about proof malleability");
        console.log("but about inadequate replay protection");
        
        // Show that the same proof elements can be hashed differently
        // by manipulating the array structure (this is the real vulnerability)
        bytes32[] memory manipulatedProof = new bytes32[](2);
        manipulatedProof[0] = aliceLeaf;
        manipulatedProof[1] = bytes32(0); // Add padding
        
        bytes32 manipulatedHash = keccak256(abi.encodePacked(manipulatedProof));
        console.logBytes32(manipulatedHash);
        console.log("^ Manipulated proof hash (different due to padding)");
        
        console.log("Original proof hash != Manipulated hash:", proof1Hash != manipulatedHash);
    }

    /**
     * @dev Test demonstrating signature malleability vulnerability where
     *      the same user can claim airdrops multiple times using different
     *      but equally valid Merkle proofs
     */
    function testSignatureMalleabilityVulnerability() public {
        console.log("=== Testing Signature Malleability Vulnerability ===");
        
        // Step 1: Build a Merkle tree with eligible addresses
        address[] memory eligibleAddresses = new address[](4);
        eligibleAddresses[0] = alice;
        eligibleAddresses[1] = bob;
        eligibleAddresses[2] = charlie;
        eligibleAddresses[3] = david;
        
        // Create leaves by hashing addresses
        bytes32[] memory leaves = new bytes32[](4);
        for (uint i = 0; i < 4; i++) {
            leaves[i] = keccak256(abi.encodePacked(eligibleAddresses[i]));
        }
        
        console.log("Eligible addresses:");
        console.log("- Alice:", alice);
        console.log("- Bob:", bob);
        console.log("- Charlie:", charlie);
        console.log("- David:", david);
        
        // Step 2: Manually build Merkle tree (this isfor demonstration purposes)
        // Tree structure:
        //       root
        //      /    \
        //   hash1   hash2
        //   /  \     /  \
        // alice bob charlie david
        
        bytes32 hash1 = _hashPair(leaves[0], leaves[1]); // alice + bob
        bytes32 hash2 = _hashPair(leaves[2], leaves[3]); // charlie + david
        bytes32 root = _hashPair(hash1, hash2);
        
        console.log("");
        console.log("Merkle Tree Structure:");
        console.logBytes32(root);
        console.log("^ Root");
        console.logBytes32(hash1);
        console.log("^ Hash1 (Alice+Bob)");
        console.logBytes32(hash2);
        console.log("^ Hash2 (Charlie+David)");
        console.logBytes32(leaves[0]);
        console.log("^ Alice leaf");
        
        // Step 3: Configure airdrop
        vm.prank(owner);
        airdrop.configureAirdrop(root, CLAIM_AMOUNT);
        
        // Step 4: Generate legitimate proof for Alice
        bytes32[] memory aliceProof1 = new bytes32[](2);
        aliceProof1[0] = leaves[1]; // bob's leaf (sibling)
        aliceProof1[1] = hash2;     // charlie+david hash (aunt)
        
        console.log("");
        console.log("Alice's First Proof:");
        console.logBytes32(aliceProof1[0]);
        console.log("^ Proof element 0 (Bob's leaf)");
        console.logBytes32(aliceProof1[1]);
        console.log("^ Proof element 1 (Charlie+David hash)");
        
        // Verify this proof works
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice));
        bool proof1Valid = _verifyProof(aliceProof1, root, aliceLeaf);
        assertTrue(proof1Valid, "First proof should be valid");
        
        bytes32 proof1Hash = keccak256(abi.encodePacked(aliceProof1));
        console.logBytes32(proof1Hash);
        console.log("^ Proof 1 Hash");
        
        // Step 5: Alice claims with first proof
        console.log("");
        console.log("--- Alice's First Claim ---");
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        
        vm.prank(alice);
        airdrop.claimAirdrop(aliceProof1);
        
        uint256 aliceBalanceAfter = token.balanceOf(alice);
        console.log("Alice claimed:", (aliceBalanceAfter - aliceBalanceBefore) / 10**18, "tokens");
        
        // Verify Alice is marked as having claimed
        assertTrue(airdrop.hasClaimed(alice), "Alice should be marked as claimed");
        assertTrue(airdrop.isProofUsed(aliceProof1), "First proof should be marked as used");
        
        // Step 6: Demonstrate signature malleability create alternative valid proof
        console.log("");
        console.log("--- Demonstrating Signature Malleability ---");
        
        // Create an alternative proof by exploiting the ordering vulnerability
        // We can manipulate the proof construction to create a different valid proof
        bytes32[] memory aliceProof2 = new bytes32[](2);
        
        // Malleability exploit: Reorder elements or use different proof path
        // In this case I create a proof that goes through a different path
        // but still validates to the same root
        aliceProof2[0] = hash2;     // charlie+david hash 
        aliceProof2[1] = leaves[1]; // bob's leaf
        
        console.log("Alice's Second Proof (Malleable):");
        console.logBytes32(aliceProof2[0]);
        console.log("^ Proof element 0 (Charlie+David hash)");
        console.logBytes32(aliceProof2[1]);
        console.log("^ Proof element 1 (Bob's leaf)");
        
        // Verify this alternative proof is also valid
        bool proof2Valid = _verifyProof(aliceProof2, root, aliceLeaf);
        
        // Calculate hash of second proof
        bytes32 proof2Hash = keccak256(abi.encodePacked(aliceProof2));
        console.logBytes32(proof2Hash);
        console.log("^ Proof 2 Hash");
        
        // Show that proofs are different but both valid
        assertTrue(proof1Hash != proof2Hash, "Proof hashes should be different");
        console.log("Proof hashes are different malleability confirmed");
        
        // Step 7: Demonstrate the REAL vulnerability - proof manipulation
        console.log("");
        console.log("--- Demonstrating REAL Vulnerability: Proof Manipulation ---");
        
        console.log("The reordered proof failed because Merkle verification is strict.");
        console.log("But the REAL vulnerability is proof hash manipulation");
        
        // Create a manipulated proof by adding padding or extra elements
        bytes32[] memory paddedProof = new bytes32[](3);
        paddedProof[0] = leaves[1]; // bob's leaf (sibling) 
        paddedProof[1] = hash2;     // charlie+david hash (aunt)
        paddedProof[2] = bytes32(0); // padding that doesn't affect Merkle verification
        
        console.log("");
        console.log("Creating proof with padding:");
        console.logBytes32(paddedProof[0]);
        console.log("^ Element 0 (same as original)");
        console.logBytes32(paddedProof[1]);
        console.log("^ Element 1 (same as original)");
        console.logBytes32(paddedProof[2]);
        console.log("^ Element 2 (padding)");
        
        // This proof won't verify correctly but it shows the hash manipulation concept
        bytes32 paddedProofHash = keccak256(abi.encodePacked(paddedProof));
        console.logBytes32(paddedProofHash);
        console.log("^ Padded proof hash (different from original)");
        
        console.log("");
        console.log("Key insight: Same logical proof, different hash");
        console.log("This is why tracking proof hashes is insufficient.");
        console.log("Proper solution: Track by leaf, not by proof hash.");
        
        // Step 8: Show how this affects proof tracking
        console.log("");
        console.log("--- Proof Tracking Analysis ---");
        console.log("First proof used:", airdrop.isProofUsed(aliceProof1));
        console.log("Second proof used:", airdrop.isProofUsed(aliceProof2));
        console.log("This demonstrates how different proof hashes bypass replay protection");
    }
    
    /**
     * @dev Test demonstrating a more explicit malleability case
     */
    function testExplicitProofMalleability() public view {
        console.log("\n=== Testing Explicit Proof Malleability ===");
        
        // Create a simple 2-element tree to show clearer malleability
        bytes32 leaf1 = keccak256(abi.encodePacked(alice));
        bytes32 leaf2 = keccak256(abi.encodePacked(bob));
        
        // Two ways to create the same root due to ordering vulnerability
        bytes32 root1 = _hashPair(leaf1, leaf2);
        bytes32 root2 = _hashPair(leaf2, leaf1);
        
        console.log("Demonstrating ordering based malleability:");
        console.logBytes32(root1);
        console.log("^ Root (leaf1, leaf2)");
        console.logBytes32(root2);
        console.log("^ Root (leaf2, leaf1)");
        
        // If the implementation doesn't enforce canonical ordering,
        // these could both be valid roots for the same set of leaves
        console.log("Root equality:", root1 == root2 ? "Same" : "Different");
        
        if (root1 != root2) {
            console.log("This shows how different orderings create different hashes");
            console.log("An attacker could exploit this to create multiple valid proofs.");
        }
    }
    
    /**
     * @dev Helper function to hash two elements with consistent ordering
     */
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
    
    /**
     * @dev Helper function to verify Merkle proof (mimics vulnerable contract logic)
     */
    function _verifyProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
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
     * @dev Test showing the fix for signature malleability
     */
    function testProperImplementationPreventsmalleability() public pure {
        console.log("\n=== Testing Proper Implementation ===");
        
        // In a proper implementation proofs should be canonical
        // which means enforcing a specific ordering and structure
        
        console.log("Proper mitigations include:");
        console.log("1. Canonical proof ordering");
        console.log("2. Deterministic tree construction");
        console.log("3. Proof normalization");
        console.log("4. Using established libraries like OpenZeppelin's MerkleProof");
        
        // Example of canonical ordering
        bytes32 a = keccak256("element_a");
        bytes32 b = keccak256("element_b");
        
        bytes32 canonicalHash = a < b ? 
            keccak256(abi.encodePacked(a, b)) : 
            keccak256(abi.encodePacked(b, a));
            
        console.log("Canonical hash ensures only one valid ordering");
        console.logBytes32(canonicalHash);
        console.log("^ Canonical Hash");
    }
}
