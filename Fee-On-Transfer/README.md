After running the following Foundry command `forge test --match-contract FeeOnTransferVulnerabilityTest -vvv` this is the output that confirms the vulnerability: 

```
Ran 4 tests for test/Test.t.sol:FeeOnTransferVulnerabilityTest
[PASS] testCalculateExactLoss() (gas: 157087)
Logs:
  === Exact Loss Calculation ===

  Alice's actual balance: 9800
  Deposit amount: 5000
  Fee percentage: 2%
  Fee charged: 100
  Vault expected to receive: 5000
  Vault actually received: 4900
  Loss per deposit: 100
  Loss percentage: 2%

[PASS] testDemonstrateVulnerability() (gas: 274800)
Logs:
  === Fee-on-Transfer Vulnerability Demonstration ===

  Step 1: Alice deposits 1000 tokens
    Alice token balance before: 9800
    Alice token balance after: 8800
    Amount Alice sent: 1000
    Amount vault received: 980
    Fee charged (2%): 20
    Alice's recorded balance in vault: 1000
  

  Step 2: Bob deposits 1000 tokens
    Amount Bob sent: 1000
    Amount vault received: 980
    Bob's recorded balance in vault: 1000
  

  Step 3: Vault Insolvency Check
    Total user balances (what vault owes): 2000
    Actual vault token balance: 1960
    Vault deficit: 40
    Is vault solvent? false
  

  Step 4: Alice withdraws her full balance
    Alice withdrew: 1000
    Alice received: 980 (includes 2% fee on withdrawal)
    Vault balance after Alice's withdrawal: 960
  

  Step 5: Bob tries to withdraw but fails due to insufficient vault balance
    Bob's recorded balance: 1000
    Vault's actual token balance: 960
    Bob's withdrawal FAILED - Vault is insolvent

[PASS] testMultipleUsersExploit() (gas: 545836)
Logs:
  === Multiple Users Exploitation Scenario ===

  All 5 users deposit 1000 tokens each:
    Total supposed deposits: 5000
    Actual vault balance: 4900
    Missing tokens due to fees: 100

  Users attempt to withdraw in order:
    User 1: SUCCESS - Withdrew 1000 tokens
    User 2: SUCCESS - Withdrew 1000 tokens
    User 3: SUCCESS - Withdrew 1000 tokens
    User 4: SUCCESS - Withdrew 1000 tokens
    User 5: FAILED - Vault only has 900 but owes 1000
  
Result: Only 4 out of 5 users could withdraw
  Remaining vault balance: 900

[PASS] testProofOfConcept() (gas: 318265)
Logs:
  === Proof of Concept: Vault Drainage ===

  Charlie deposited: 5000
  Vault actually received: 4900
  Deficit created: 100

  Alice and Bob each deposited: 1000
  Total tracked deposits: 7000
  Actual vault balance: 6860
  Total deficit: 140

  Charlie withdrew successfully
  Vault balance after Charlie's withdrawal: 1860
  Amount owed to Alice and Bob: 2000
  
Result: Vault is drained, later depositors lose funds

Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 5.92ms (5.43ms CPU time)
```

