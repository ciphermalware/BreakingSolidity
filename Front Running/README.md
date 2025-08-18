After running the following Foundry test command `forge test --match-test testGriefAttackForceValidator -vvv` this is the output that confirms the vulnerability:


```
Ran 1 test for test/StakingFrontRunning.t.sol:StakingFrontRunningTest
[PASS] testGriefAttackForceValidator() (gas: 226684)
Logs:
  === Testing Grief Attack: Forced Validator Registration ===
  Initial state:
  - Alice wants to delegate 1000 tokens to Bob
  - Alice is not a validator
  - Bob is a legitimate validator with 5% commission
  
  --- Alice's Intended Delegation Preview ---
  Can delegate to Bob: true
  Reason: Delegation would succeed
  
  --- GRIEF ATTACK IN PROGRESS ---
  1. Attacker monitors mempool and sees Alice's pending delegation
  2. Attacker front runs with malicious transaction
  Attacker forces Alice to delegate 1 wei to herself...
  Attack successful! Cost to attacker: 1 wei
  
  --- ATTACK CONSEQUENCES ---
  Alice is now a 'registered validator': true
  Alice's delegate address: 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6
  Alice's bonded amount: 1 wei
  Alice delegates to herself with minimal amount
  
  --- ALICE'S TRANSACTION FAILS ---
  3. Alice's original transaction executes and FAILS
  Alice can now delegate to Bob: false
  Failure reason: Registered validators cannot delegate to other addresses
  Alice's delegation to Bob REVERTED
  
  --- VICTIM IMPACT ANALYSIS ---
  Alice is now stuck as an unintended validator:
  - Cannot delegate to her preferred validator (Bob)
  - Forced to be a validator with just 1 wei stake
  - Must now accept delegations and run validator infrastructure
  - Attack cost: 1 wei (~$0.000001)
  - Victim disruption: Complete protocol usage blocked

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 3.15ms (1.15ms CPU time)
```
