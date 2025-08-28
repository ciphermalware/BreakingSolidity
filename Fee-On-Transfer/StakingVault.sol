// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeOnTransferToken
 * @dev A token that charges a 2% fee on every transfer
 */
contract FeeOnTransferToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public name = "FeeToken";
    string public symbol = "FEE";
    uint8 public decimals = 18;
    
    uint256 public constant FEE_PERCENTAGE = 2; // 2% fee
    address public feeRecipient;
    
    constructor() {
        feeRecipient = msg.sender;
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens
    }
    
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        
        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        
        _transferWithFee(from, to, amount);
        return true;
    }
    
    function _transferWithFee(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        
        uint256 senderBalance = _balances[from];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        
        // Calculate fee 
        uint256 fee = (amount * FEE_PERCENTAGE) / 100;
        uint256 amountAfterFee = amount - fee;
        
        // Update balances
        unchecked {
            _balances[from] = senderBalance - amount;
        }
        _balances[to] += amountAfterFee;
        _balances[feeRecipient] += fee;
        
        emit Transfer(from, to, amountAfterFee);
        if (fee > 0) {
            emit Transfer(from, feeRecipient, fee);
        }
    }
    
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero address");
        
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
}

/**
 * @title VulnerableStakingVault
 * @dev A staking vault that is vulnerable to fee on transfer tokens
 * The vulnerability: Contract assumes it receives the exact amount sent by users
 */
contract VulnerableStakingVault is Ownable {
    IERC20 public stakingToken;
    
    // User balances, vulnerable tracks sent amount, not received amount
    mapping(address => uint256) public userBalances;
    
    // Total staked amount, vulnerable: doesn't account for fees
    uint256 public totalStaked;
    
    // Reward rate (tokens per second per token staked)
    uint256 public rewardRate = 100; // 100 wei per second per token
    
    // User reward tracking
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewards;
    
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }
    
    /**
     * @dev Assumes contract receives the exact amount sent
     * For fee on transfer tokens, the contract receives less than 'amount'
     * but credits the user with the full 'amount'
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Cannot deposit 0");
        
        // Update rewards before changing balance
        _updateRewards(msg.sender);
        
        // Vulnerability: Contract assumes it receives 'amount' tokens
        // but for fee-on-transfer tokens, it receives less (amount - fee)
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        // Vulnerability: Credits user with full amount not actual received amount
        userBalances[msg.sender] += amount;
        totalStaked += amount;
        
        emit Deposited(msg.sender, amount);
    }
    
    /**
     * @dev Withdraw staked tokens
     * This will fail for later users as contract doesn't have enough tokens
     */
    function withdraw(uint256 amount) public {
        require(amount > 0, "Cannot withdraw 0");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        // Update rewards before changing balance
        _updateRewards(msg.sender);
        
        userBalances[msg.sender] -= amount;
        totalStaked -= amount;
        
        // This transfer will eventually fail when contract runs out of tokens
        stakingToken.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Withdraw all staked tokens
     */
    function withdrawAll() external {
        uint256 balance = userBalances[msg.sender];
        if (balance > 0) {
            withdraw(balance);
        }
    }
    
    /**
     * @dev Calculate pending rewards for a user
     */
    function pendingRewards(address user) public view returns (uint256) {
        if (userBalances[user] == 0) {
            return rewards[user];
        }
        
        uint256 timeDiff = block.timestamp - lastUpdateTime[user];
        uint256 reward = (userBalances[user] * rewardRate * timeDiff) / 1e18;
        return rewards[user] + reward;
    }
    
    /**
     * @dev Update rewards for a user
     */
    function _updateRewards(address user) internal {
        rewards[user] = pendingRewards(user);
        lastUpdateTime[user] = block.timestamp;
    }
    
    /**
     * @dev Claim accumulated rewards
     */
    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = rewards[msg.sender];
        
        if (reward > 0) {
            rewards[msg.sender] = 0;
            emit RewardsClaimed(msg.sender, reward);
        }
    }
    
    /**
     * @dev Emergency function to check actual token balance
     * This will reveal the discrepancy between expected and actual balance
     */
    function getActualTokenBalance() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }
    
    /**
     * @dev Check if the vault is solvent
     * Returns false if actual balance < total tracked deposits
     */
    function isSolvent() external view returns (bool) {
        return stakingToken.balanceOf(address(this)) >= totalStaked;
    }
}
