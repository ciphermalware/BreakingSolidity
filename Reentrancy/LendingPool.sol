// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VulnerableLendingPool
 * @dev A lending pool vulnerable to reentrancy attacks
 * Users can deposit ETH as collateral and borrow tokens against it
 * The vulnerability is in the withdrawCollateral function
 */
contract VulnerableLendingPool {
    IERC20 public loanToken;
    
    // User collateral balances (in ETH)
    mapping(address => uint256) public collateralBalances;
    
    // User borrowed amounts (in tokens)
    mapping(address => uint256) public borrowedAmounts;
    
    // Total ETH in the pool
    uint256 public totalCollateral;
    
    // Collateral ratio: 150% (users must maintain 1.5x collateral value)
    uint256 public constant COLLATERAL_RATIO = 150;
    
    // Price of 1 ETH in loan tokens (simplified: 1 ETH = 2000 tokens)
    uint256 public constant ETH_PRICE = 2000 * 1e18;
    
    // Pool's token reserve for lending
    uint256 public tokenReserve;
    
    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event TokensBorrowed(address indexed user, uint256 amount);
    event TokensRepaid(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    
    constructor(address _loanToken) {
        loanToken = IERC20(_loanToken);
    }
    
    /**
     * @dev Deposit ETH as collateral
     */
    function depositCollateral() external payable {
        require(msg.value > 0, "Must deposit ETH");
        
        collateralBalances[msg.sender] += msg.value;
        totalCollateral += msg.value;
        
        emit CollateralDeposited(msg.sender, msg.value);
    }
    
    /**
     * @dev Vulnerable function, withdraws collateral
     * Vulnerability: Sends ETH before updating state (Classic Reentrancy)
     */
    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(collateralBalances[msg.sender] >= amount, "Insufficient collateral");
        
        // Check if withdrawal would violate collateral ratio
        uint256 remainingCollateral = collateralBalances[msg.sender] - amount;
        require(
            getMaxBorrowAmount(remainingCollateral) >= borrowedAmounts[msg.sender],
            "Would violate collateral ratio"
        );
        
        // External call before state update
        // Attacker can re enter here before balances are updated
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
        
        // State updates happen AFTER the external call (VULNERABLE!)
        collateralBalances[msg.sender] -= amount;
        totalCollateral -= amount;
        
        emit CollateralWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Borrow tokens against collateral
     */
    function borrowTokens(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(tokenReserve >= amount, "Insufficient token reserve");
        
        uint256 maxBorrow = getMaxBorrowAmount(collateralBalances[msg.sender]);
        uint256 newBorrowTotal = borrowedAmounts[msg.sender] + amount;
        
        require(newBorrowTotal <= maxBorrow, "Exceeds max borrow amount");
        
        borrowedAmounts[msg.sender] = newBorrowTotal;
        tokenReserve -= amount;
        
        require(loanToken.transfer(msg.sender, amount), "Token transfer failed");
        
        emit TokensBorrowed(msg.sender, amount);
    }
    
    /**
     * @dev Repay borrowed tokens
     */
    function repayTokens(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(borrowedAmounts[msg.sender] >= amount, "Repaying too much");
        
        require(
            loanToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        
        borrowedAmounts[msg.sender] -= amount;
        tokenReserve += amount;
        
        emit TokensRepaid(msg.sender, amount);
    }
    
    /**
     * @dev also vulnerable, emergency withdraw all collateral
     * Another reentrancy vulnerable function
     */
    function emergencyWithdraw() external {
        uint256 balance = collateralBalances[msg.sender];
        require(balance > 0, "No collateral to withdraw");
        require(borrowedAmounts[msg.sender] == 0, "Must repay loans first");
        
        // VULNERABILITY: Same pattern - external call before state update
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "ETH transfer failed");
        
        collateralBalances[msg.sender] = 0;
        totalCollateral -= balance;
        
        emit EmergencyWithdraw(msg.sender, balance);
    }
    
    /**
     * @dev Calculate maximum borrow amount based on collateral
     */
    function getMaxBorrowAmount(uint256 collateral) public pure returns (uint256) {
        // Max borrow = (collateral value in tokens * 100) / COLLATERAL_RATIO
        return (collateral * ETH_PRICE * 100) / (COLLATERAL_RATIO * 1e18);
    }
    
    /**
     * @dev Get user's current collateral ratio
     */
    function getUserCollateralRatio(address user) external view returns (uint256) {
        if (borrowedAmounts[user] == 0) return type(uint256).max;
        
        uint256 collateralValue = collateralBalances[user] * ETH_PRICE / 1e18;
        return (collateralValue * 100) / borrowedAmounts[user];
    }
    
    /**
     * @dev Add tokens to the lending reserve (for testing)
     */
    function addTokenReserve(uint256 amount) external {
        require(
            loanToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        tokenReserve += amount;
    }
    
    /**
     * @dev Get contract's ETH balance
     */
    function getPoolBalance() external view returns (uint256) {
        return address(this).balance;
    }
}


