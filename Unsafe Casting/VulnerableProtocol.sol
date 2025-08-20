// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Based on real Code4rena findings in production protocols
 */
contract VulnerableProtocol is Ownable {
    
    // Protocol tokens
    IERC20 public immutable underlying; // e.g., USDC
    IERC20 public immutable protocolToken; // Protocol's native token
    
    // Oracle interface
    IPCVOracle public oracle;
    
    // Protocol state
    uint256 public totalDeposits;
    uint256 public protocolEquity; // VULNERABILITY: Should be int256 but stored as uint256
    uint256 public lastUpdateTime;
    uint256 public constant EQUITY_THRESHOLD = 1000000e6; // 1M USDC minimum equity
    
    // User balances
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userShares;
    uint256 public totalShares;
    
    // Emergency controls
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;
    
    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdrawal(address indexed user, uint256 amount, uint256 shares);
    event EquityRecalculated(int256 oracleValue, uint256 protocolEquity);
    event EmergencyAction(string reason, uint256 equity);
    
    constructor(
        address _underlying,
        address _protocolToken,
        address _oracle
    ) {
        underlying = IERC20(_underlying);
        protocolToken = IERC20(_protocolToken);
        oracle = IPCVOracle(_oracle);
        protocolEquity = 0;
        lastUpdateTime = block.timestamp;
    }
    
    /**
     * @dev Recalculate protocol equity using oracle data
     * 
     * @notice VULNERABILITY: Unsafe casting from int256 to uint256
     *         If oracle returns negative value, it wraps to huge positive number
     *         This can cause catastrophic miscalculations in protocol solvency
     */
    function recalculateEquity() external {
        // Get equity from oracle (returns int256 - can be negative!)
        int256 newProtocolEquity = oracle.pcvStats();
        
        // UNSAFE CAST: No check for negative values!
        // If newProtocolEquity is negative, this becomes a huge positive number
        protocolEquity = uint256(newProtocolEquity);
        
        lastUpdateTime = block.timestamp;
        
        emit EquityRecalculated(newProtocolEquity, protocolEquity);
        
        // Protocol logic based on equity
        _handleEquityChange();
    }
    
    /**
     * @dev Deposit underlying tokens to earn yield
     */
    function deposit(uint256 _amount) external {
        require(depositsEnabled, "Deposits disabled");
        require(_amount > 0, "Amount must be positive");
        
        // Update equity before calculating shares
        int256 currentEquity = oracle.pcvStats();
        protocolEquity = uint256(currentEquity); // VULNERABILITY: Same unsafe cast
        
        // Calculate shares based on current equity
        uint256 shares = _calculateShares(_amount);
        
        // Update state
        userDeposits[msg.sender] += _amount;
        userShares[msg.sender] += shares;
        totalShares += shares;
        totalDeposits += _amount;
        
        // Transfer tokens
        require(underlying.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        emit Deposit(msg.sender, _amount, shares);
    }
    
    /**
     * @dev Withdraw tokens based on share ownership
     */
    function withdraw(uint256 _shares) external {
        require(withdrawalsEnabled, "Withdrawals disabled");
        require(_shares > 0, "Shares must be positive");
        require(userShares[msg.sender] >= _shares, "Insufficient shares");
        
        // Update equity before calculating withdrawal
        int256 currentEquity = oracle.pcvStats();
        protocolEquity = uint256(currentEquity); // VULNERABILITY: Unsafe cast again
        
        // Calculate withdrawal amount based on current equity
        uint256 withdrawAmount = _calculateWithdrawal(_shares);
        
        // Update state
        userShares[msg.sender] -= _shares;
        totalShares -= _shares;
        userDeposits[msg.sender] -= withdrawAmount; // Simplified logic
        totalDeposits -= withdrawAmount;
        
        // Transfer tokens
        require(underlying.transfer(msg.sender, withdrawAmount), "Transfer failed");
        
        emit Withdrawal(msg.sender, withdrawAmount, _shares);
    }
    
    /**
     * @dev Calculate shares for deposit amount
     */
    function _calculateShares(uint256 _amount) internal view returns (uint256) {
        if (totalShares == 0 || protocolEquity == 0) {
            return _amount; // 1:1 for first deposit
        }
        
        // VULNERABILITY: If protocolEquity is artificially high due to unsafe cast,
        // users get fewer shares than they should
        return (_amount * totalShares) / protocolEquity;
    }
    
    /**
     * @dev Calculate withdrawal amount for shares
     */
    function _calculateWithdrawal(uint256 _shares) internal view returns (uint256) {
        require(totalShares > 0, "No shares exist");
        
        // VULNERABILITY: If protocolEquity is artificially high due to unsafe cast,
        // users can withdraw more than the protocol actually has
        return (_shares * protocolEquity) / totalShares;
    }
    
    /**
     * @dev Handle equity changes and emergency conditions
     */
    function _handleEquityChange() internal {
        // VULNERABILITY: Due to unsafe casting, negative equity appears as huge positive
        // This logic will never trigger when it should for actual negative equity
        if (protocolEquity < EQUITY_THRESHOLD) {
            depositsEnabled = false;
            emit EmergencyAction("Low equity detected", protocolEquity);
        } else {
            depositsEnabled = true;
        }
        
        // Check for impossibly high equity (might indicate casting issue)
        if (protocolEquity > type(uint128).max) {
            withdrawalsEnabled = false;
            emit EmergencyAction("Abnormally high equity - possible casting error", protocolEquity);
        }
    }
    
    /**
     * @dev Get current protocol status
     */
    function getProtocolStatus() external view returns (
        uint256 _protocolEquity,
        uint256 _totalDeposits,
        uint256 _totalShares,
        bool _depositsEnabled,
        bool _withdrawalsEnabled
    ) {
        return (protocolEquity, totalDeposits, totalShares, depositsEnabled, withdrawalsEnabled);
    }
    
    /**
     * @dev Preview potential issues with oracle value
     */
    function previewEquityCalculation() external view returns (
        int256 oracleValue,
        uint256 unsafeCastResult,
        bool wouldCauseIssue
    ) {
        oracleValue = oracle.pcvStats();
        unsafeCastResult = uint256(oracleValue); // Demonstrate the unsafe cast
        wouldCauseIssue = oracleValue < 0; // True if negative value would cause issues
        
        return (oracleValue, unsafeCastResult, wouldCauseIssue);
    }
    
    /**
     * @dev Emergency functions
     */
    function emergencyPause() external onlyOwner {
        depositsEnabled = false;
        withdrawalsEnabled = false;
    }
    
    function emergencyUnpause() external onlyOwner {
        depositsEnabled = true;
        withdrawalsEnabled = true;
    }
    
    function updateOracle(address _newOracle) external onlyOwner {
        oracle = IPCVOracle(_newOracle);
    }
}

/**
 * @title IPCVOracle
 * @dev Interface for PCV (Protocol Controlled Value) Oracle
 */
interface IPCVOracle {
    /**
     * @dev Returns protocol equity value
     * @return equity Protocol equity (can be negative!)
     */
    function pcvStats() external view returns (int256 equity);
}

/**
 * @title MockPCVOracle
 * @dev Mock oracle for testing that can return negative values
 */
contract MockPCVOracle is IPCVOracle {
    int256 private _equity;
    address public owner;
    
    constructor() {
        owner = msg.sender;
        _equity = 1000000e6; // Start with 1M positive equity
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    function pcvStats() external view override returns (int256) {
        return _equity;
    }
    
    function setEquity(int256 _newEquity) external onlyOwner {
        _equity = _newEquity;
    }
    
    // Simulate market crash - protocol goes negative
    function simulateMarketCrash() external onlyOwner {
        _equity = -500000e6; // -500k equity (protocol is insolvent)
    }
    
    // Simulate recovery
    function simulateRecovery() external onlyOwner {
        _equity = 2000000e6; // 2M positive equity
    }
    
    // Set extremely negative value to show casting issue
    function setExtremeNegative() external onlyOwner {
        _equity = type(int256).min; // Most negative possible value
    }
}

/**
 * @title MockERC20
 * @dev Mock token for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 10000000e6); // 10M tokens with 6 decimals
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6; // USDC has 6 decimals
    }
}
