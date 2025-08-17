// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VulnerableDEX
 */
contract VulnerableDEX is ReentrancyGuard, Ownable {
    
    // Trading pair tokens
    IERC20 public immutable baseToken;   // e.g., SPARTA
    IERC20 public immutable quoteToken;  // e.g., USDC
    
    // Pool state
    uint256 public baseAmount;    // Amount of base token in pool
    uint256 public quoteAmount;   // Amount of quote token in pool
    
    // Fee configuration
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFee = 30; // 0.3% fee
    
    // Pool metrics
    uint256 public totalVolume;
    uint256 public totalFees;
    
    // Events
    event Swap(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );
    
    event LiquidityAdded(
        address indexed provider,
        uint256 baseAmount,
        uint256 quoteAmount
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 baseAmount,
        uint256 quoteAmount
    );

    constructor(address _baseToken, address _quoteToken) {
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }
    
    /**
     * @dev Add liquidity to the pool
     * @param _baseAmount Amount of base token to add
     * @param _quoteAmount Amount of quote token to add
     */
    function addLiquidity(uint256 _baseAmount, uint256 _quoteAmount) external nonReentrant {
        require(_baseAmount > 0 && _quoteAmount > 0, "Amounts must be positive");
        
        // Transfer tokens from user
        require(baseToken.transferFrom(msg.sender, address(this), _baseAmount), "Base transfer failed");
        require(quoteToken.transferFrom(msg.sender, address(this), _quoteAmount), "Quote transfer failed");
        
        // Update pool state
        baseAmount += _baseAmount;
        quoteAmount += _quoteAmount;
        
        emit LiquidityAdded(msg.sender, _baseAmount, _quoteAmount);
    }
    
    /**
     * @dev Swap base token for quote token
     * @param _amountIn Amount of base token to swap
     * 
     * @notice VULNERABILITY: No slippage protection (minAmountOut) or deadline
     *         This allows front-running and sandwich attacks where:
     *         1. Attacker front-runs with large trade to worsen price
     *         2. Victim's trade executes at manipulated price  
     *         3. Attacker back-runs to extract profit
     */
    function swapBaseToQuote(uint256 _amountIn) external nonReentrant returns (uint256 amountOut) {
        require(_amountIn > 0, "Amount must be positive");
        require(baseAmount > 0 && quoteAmount > 0, "Pool not initialized");
        
        // VULNERABLE: No slippage protection - users can't specify minimum output
        // VULNERABLE: No deadline check - transaction can be delayed indefinitely
        
        // Calculate output using constant product formula (x * y = k)
        (uint256 _amountOut, uint256 _fee) = _swapBaseToQuote(_amountIn);
        
        // Transfer tokens
        require(baseToken.transferFrom(msg.sender, address(this), _amountIn), "Input transfer failed");
        require(quoteToken.transfer(msg.sender, _amountOut), "Output transfer failed");
        
        emit Swap(msg.sender, address(baseToken), address(quoteToken), _amountIn, _amountOut, _fee);
        
        return _amountOut;
    }
    
    /**
     * @dev Swap quote token for base token  
     * @param _amountIn Amount of quote token to swap
     * 
     * @notice vulnerability: Same issues as swapBaseToQuote, no slippage/deadline protection
     */
    function swapQuoteToBase(uint256 _amountIn) external nonReentrant returns (uint256 amountOut) {
        require(_amountIn > 0, "Amount must be positive");
        require(baseAmount > 0 && quoteAmount > 0, "Pool not initialized");
        
        // VULNERABLE: No slippage protection
        // VULNERABLE: No deadline check
        
        (uint256 _amountOut, uint256 _fee) = _swapQuoteToBase(_amountIn);
        
        require(quoteToken.transferFrom(msg.sender, address(this), _amountIn), "Input transfer failed");
        require(baseToken.transfer(msg.sender, _amountOut), "Output transfer failed");
        
        emit Swap(msg.sender, address(quoteToken), address(baseToken), _amountIn, _amountOut, _fee);
        
        return _amountOut;
    }
    
    /**
     * @dev Internal function to calculate base-to-quote swap 
     * @param _x Amount of base token input
     * @return _y Amount of quote token output
     * @return _fee Fee amount in base token terms
     * 
     * @notice This mirrors the vulnerable Code4rena finding, no slippage checks
     */
    function _swapBaseToQuote(uint256 _x) internal returns (uint256 _y, uint256 _fee) {
        uint256 _X = baseAmount;    // Current base reserves
        uint256 _Y = quoteAmount;   // Current quote reserves
        
        // Calculate swap output using constant product formula: (X + dx) * (Y - dy) = X * Y
        // Solving for dy: dy = (Y * dx) / (X + dx)
        _y = calcSwapOutput(_x, _X, _Y);
        
        // Calculate fee (as percentage of input)
        _fee = calcSwapFee(_x, _X, _Y);
        
        // Update pool amounts (this is where the manipulation happens)
        _setPoolAmounts(_X + _x, _Y - _y);
        
        // Add fees to metrics
        _addPoolMetrics(_fee);
        
        return (_y, _fee);
    }
    
    /**
     * @dev Internal function to calculate quote-to-base swap
     */
    function _swapQuoteToBase(uint256 _x) internal returns (uint256 _y, uint256 _fee) {
        uint256 _X = quoteAmount;   // Current quote reserves (input side)
        uint256 _Y = baseAmount;    // Current base reserves (output side)
        
        _y = calcSwapOutput(_x, _X, _Y);
        _fee = calcSwapFee(_x, _X, _Y);
        
        _setPoolAmounts(_Y - _y, _X + _x); // base, quote
        _addPoolMetrics(_fee);
        
        return (_y, _fee);
    }
    
    /**
     * @dev Calculate swap output using constant product formula
     * @param amountIn Input amount
     * @param reserveIn Input token reserves
     * @param reserveOut Output token reserves
     * @return amountOut Output amount
     */
    function calcSwapOutput(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        // Apply fee (0.3% fee means 99.7% goes to calculation)
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        
        amountOut = numerator / denominator;
    }
    
    /**
     * @dev Calculate swap fee
     */
    function calcSwapFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        public view returns (uint256 fee) {
        // Fee is percentage of input amount
        fee = (amountIn * swapFee) / FEE_DENOMINATOR;
    }
    
    /**
     * @dev Update pool amounts
     */
    function _setPoolAmounts(uint256 _baseAmount, uint256 _quoteAmount) internal {
        baseAmount = _baseAmount;
        quoteAmount = _quoteAmount;
    }
    
    /**
     * @dev Add metrics for fees and volume
     */
    function _addPoolMetrics(uint256 _fee) internal {
        totalFees += _fee;
        totalVolume += _fee; // Simplified
    }
    
    /**
     * @dev Get current price 
     * @notice This can be manipulated by large trades
     */
    function getCurrentPrice() external view returns (uint256 price) {
        require(baseAmount > 0 && quoteAmount > 0, "Pool not initialized");
        // Price = quoteAmount / baseAmount (how many quote tokens per base token)
        price = (quoteAmount * 1e18) / baseAmount;
    }
    
    /**
     * @dev Preview swap output (used by front-runners to plan attacks)
     * @param amountIn Input amount
     * @param tokenIn Input token address
     * @return amountOut Expected output amount
     * 
     * @notice vulnerability: This function helps attackers calculate optimal sandwich sizes
     */
    function previewSwap(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be positive");
        
        if (tokenIn == address(baseToken)) {
            amountOut = calcSwapOutput(amountIn, baseAmount, quoteAmount);
        } else if (tokenIn == address(quoteToken)) {
            amountOut = calcSwapOutput(amountIn, quoteAmount, baseAmount);
        } else {
            revert("Invalid token");
        }
    }
    
    /**
     * @dev Get pool reserves
     */
    function getReserves() external view returns (uint256 _baseAmount, uint256 _quoteAmount) {
        return (baseAmount, quoteAmount);
    }
    
    /**
     * @dev Emergency withdrawal (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 baseBalance = baseToken.balanceOf(address(this));
        uint256 quoteBalance = quoteToken.balanceOf(address(this));
        
        if (baseBalance > 0) {
            baseToken.transfer(owner(), baseBalance);
        }
        if (quoteBalance > 0) {
            quoteToken.transfer(owner(), quoteBalance);
        }
    }
}

/**
 * @title MockERC20
 * @dev Simple ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) 
        ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
