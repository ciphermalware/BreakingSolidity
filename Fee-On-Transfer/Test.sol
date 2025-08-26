// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingVault.sol";

contract FeeOnTransferVulnerabilityTest is Test {
    FeeOnTransferToken public token;
    VulnerableStakingVault public vault;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public owner;
    
    uint256 constant INITIAL_BALANCE = 10000 * 1e18;
    uint256 constant DEPOSIT_AMOUNT = 1000 * 1e18;
    
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    
    function setUp() public {
        owner = address(this);
        
        // Deploy contracts
        token = new FeeOnTransferToken();
        vault = new VulnerableStakingVault(address(token));
        
        // Setup test users with tokens
        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);
        token.transfer(charlie, INITIAL_BALANCE);
        
        // Label addresses for better trace output
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(address(vault), "VulnerableVault");
        vm.label(address(token), "FeeToken");
    }
    
    function testDemonstrateVulnerability() public {
        console.log("=== Fee on transfer vulnerability demonstration ===\n");
        
        // Step 1: Alice deposits tokens
        console.log("Step 1: Alice deposits 1000 tokens");
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 vaultBalanceBefore = token.balanceOf(address(vault));
        
        vault.deposit(DEPOSIT_AMOUNT);
        
        uint256 aliceBalanceAfter = token.balanceOf(alice);
        uint256 vaultBalanceAfter = token.balanceOf(address(vault));
        
        console.log("  Alice token balance before: %s", aliceBalanceBefore / 1e18);
        console.log("  Alice token balance after: %s", aliceBalanceAfter / 1e18);
        console.log("  Amount Alice sent: %s", DEPOSIT_AMOUNT / 1e18);
        console.log("  Amount vault received: %s", (vaultBalanceAfter - vaultBalanceBefore) / 1e18);
        console.log("  Fee charged (2%%): %s", (DEPOSIT_AMOUNT * 2 / 100) / 1e18);
        console.log("  Alice's recorded balance in vault: %s", vault.userBalances(alice) / 1e18);
        
        // Assert the vulnerability exists
        assertEq(vault.userBalances(alice), DEPOSIT_AMOUNT, "Vault credited full amount");
        assertEq(vaultBalanceAfter - vaultBalanceBefore, DEPOSIT_AMOUNT * 98 / 100, "Vault received less due to fee");
        
        vm.stopPrank();
        
        console.log("\n");
        
        // Step 2: Bob deposits tokens
        console.log("Step 2: Bob deposits 1000 tokens");
        vm.startPrank(bob);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        
        vaultBalanceBefore = token.balanceOf(address(vault));
        vault.deposit(DEPOSIT_AMOUNT);
        vaultBalanceAfter = token.balanceOf(address(vault));
        
        console.log("  Amount Bob sent: %s", DEPOSIT_AMOUNT / 1e18);
        console.log("  Amount vault received: %s", (vaultBalanceAfter - vaultBalanceBefore) / 1e18);
        console.log("  Bob's recorded balance in vault: %s", vault.userBalances(bob) / 1e18);
        
        vm.stopPrank();
        
        console.log("\n");
        
        // Step 3 Show vault insolvency
        console.log("Step 3: Vault Insolvency Check");
        uint256 totalUserBalances = vault.userBalances(alice) + vault.userBalances(bob);
        uint256 actualVaultBalance = token.balanceOf(address(vault));
        
        console.log("  Total user balances (what vault owes): %s", totalUserBalances / 1e18);
        console.log("  Actual vault token balance: %s", actualVaultBalance / 1e18);
        console.log("  Vault deficit: %s", (totalUserBalances - actualVaultBalance) / 1e18);
        console.log("  Is vault solvent? %s", vault.isSolvent());
        
        assertEq(vault.isSolvent(), false, "Vault should be insolvent");
        
        console.log("\n");
        
        // Step 4: Alice withdraws successfully (first withdrawer)
        console.log("Step 4: Alice withdraws her full balance");
        vm.startPrank(alice);
        
        uint256 aliceBalanceBeforeWithdraw = token.balanceOf(alice);
        vault.withdrawAll();
        uint256 aliceBalanceAfterWithdraw = token.balanceOf(alice);
        
        console.log("  Alice withdrew: %s", DEPOSIT_AMOUNT / 1e18);
        console.log("  Alice received: %s (includes 2%% fee on withdrawal)", 
                   (aliceBalanceAfterWithdraw - aliceBalanceBeforeWithdraw) / 1e18);
        console.log("  Vault balance after Alice's withdrawal: %s", 
                   token.balanceOf(address(vault)) / 1e18);
        
        vm.stopPrank();
        
        console.log("\n");
        
        // Step 5 Bob tries to withdraw but fails
        console.log("Step 5: Bob tries to withdraw but fails due to insufficient vault balance");
        vm.startPrank(bob);
        
        console.log("  Bob's recorded balance: %s", vault.userBalances(bob) / 1e18);
        console.log("  Vault's actual token balance: %s", token.balanceOf(address(vault)) / 1e18);
        
        // This should revert because vault doesn't have enough tokens
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.withdrawAll();
        
        console.log("  Bob's withdrawal FAILED - Vault is insolvent!");
        
        vm.stopPrank();
    }
    
    function testMultipleUsersExploit() public {
        console.log("=== Multiple Users Exploitation Scenario ===\n");
        
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = address(0x4);
        users[4] = address(0x5);
        
        // Give tokens to additional users
        token.transfer(users[3], INITIAL_BALANCE);
        token.transfer(users[4], INITIAL_BALANCE);
        
        
        console.log("All 5 users deposit 1000 tokens each:");
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            token.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
        
        console.log("  Total supposed deposits: %s", (DEPOSIT_AMOUNT * 5) / 1e18);
        console.log("  Actual vault balance: %s", token.balanceOf(address(vault)) / 1e18);
        console.log("  Missing tokens due to fees: %s\n", 
                   ((DEPOSIT_AMOUNT * 5) - token.balanceOf(address(vault))) / 1e18);
        
        // Try to withdraw in order
        console.log("Users attempt to withdraw in order:");
        uint256 successfulWithdrawals = 0;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            
            uint256 userBalance = vault.userBalances(users[i]);
            uint256 vaultBalance = token.balanceOf(address(vault));
            
            if (vaultBalance >= userBalance) {
                vault.withdrawAll();
                successfulWithdrawals++;
                console.log("  User %s: SUCCESS - Withdrew %s tokens", 
                           i + 1, userBalance / 1e18);
            } else {
                console.log("  User %s: FAILED - Vault only has %s but owes %s", 
                           i + 1, vaultBalance / 1e18, userBalance / 1e18);
                break;
            }
            
            vm.stopPrank();
        }
        
        console.log("\nResult: Only %s out of 5 users could withdraw!", successfulWithdrawals);
        console.log("Remaining vault balance: %s", token.balanceOf(address(vault)) / 1e18);
    }
    
    function testCalculateExactLoss() public {
        console.log("=== Exact Loss Calculation ===\n");
        
        // Alice received 9800 tokens (10000 - 2% fee) in setUp
        // So we'll deposit an amount she can actually afford
        uint256 depositAmount = 5000 * 1e18;
        uint256 feePercentage = 2;
        
        vm.startPrank(alice);
        
        // Check Alice's actual balance
        uint256 aliceBalance = token.balanceOf(alice);
        console.log("Alice's actual balance: %s", aliceBalance / 1e18);
        
        token.approve(address(vault), depositAmount);
        
        uint256 vaultBalanceBefore = token.balanceOf(address(vault));
        vault.deposit(depositAmount);
        uint256 vaultBalanceAfter = token.balanceOf(address(vault));
        
        uint256 actualReceived = vaultBalanceAfter - vaultBalanceBefore;
        uint256 expectedReceived = depositAmount;
        uint256 feeCharged = depositAmount * feePercentage / 100;
        uint256 loss = expectedReceived - actualReceived;
        
        console.log("Deposit amount: %s", depositAmount / 1e18);
        console.log("Fee percentage: %s%%", feePercentage);
        console.log("Fee charged: %s", feeCharged / 1e18);
        console.log("Vault expected to receive: %s", expectedReceived / 1e18);
        console.log("Vault actually received: %s", actualReceived / 1e18);
        console.log("Loss per deposit: %s", loss / 1e18);
        console.log("Loss percentage: %s%%", (loss * 100) / depositAmount);
        
        assertEq(loss, feeCharged, "Loss equals the transfer fee");
        
        vm.stopPrank();
    }
    
    function testProofOfConcept() public {
        console.log("=== Proof of Concept: Vault Drainage ===\n");
        
        // Charlie deposits a large amount
        uint256 largeDeposit = 5000 * 1e18;
        vm.startPrank(charlie);
        token.approve(address(vault), largeDeposit);
        vault.deposit(largeDeposit);
        vm.stopPrank();
        
        console.log("Charlie deposited: %s", largeDeposit / 1e18);
        console.log("Vault actually received: %s", token.balanceOf(address(vault)) / 1e18);
        console.log("Deficit created: %s\n", (largeDeposit * 2 / 100) / 1e18);
        
        // Alice and Bob deposit smaller amounts
        vm.startPrank(alice);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        console.log("Alice and Bob each deposited: %s", DEPOSIT_AMOUNT / 1e18);
        console.log("Total tracked deposits: %s", vault.totalStaked() / 1e18);
        console.log("Actual vault balance: %s", token.balanceOf(address(vault)) / 1e18);
        console.log("Total deficit: %s\n", 
                   (vault.totalStaked() - token.balanceOf(address(vault))) / 1e18);
        
        // Charlie withdraws first, taking advantage of the deficit
        vm.startPrank(charlie);
        vault.withdrawAll();
        console.log("Charlie withdrew successfully!");
        vm.stopPrank();
        
        // Now others cannot withdraw their full amounts
        console.log("Vault balance after Charlie's withdrawal: %s", 
                   token.balanceOf(address(vault)) / 1e18);
        console.log("Amount owed to Alice and Bob: %s", 
                   (vault.userBalances(alice) + vault.userBalances(bob)) / 1e18);
        
        assertTrue(
            token.balanceOf(address(vault)) < vault.userBalances(alice) + vault.userBalances(bob),
            "Vault cannot cover remaining deposits"
        );
        
        console.log("\nResult: Vault is drained, later depositors lose funds!");
    }
}
