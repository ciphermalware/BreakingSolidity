// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VulnerableStakingProtocol
 * @dev A staking protocol that allows users to delegate tokens to validators
 *      It has a front- unning vulnerability where attackers can force users
 *      to become validators against their will
 * @notice Based on real Code4rena/bug bounty finding worth $2,500
 *        
 */
contract VulnerableStakingProtocol is Ownable {
    
    // The staking token
    IERC20 public immutable stakingToken;
    
    // Delegation status enum
    enum DelegatorStatus {
        Unbonded,
        Bonded,
        Pending
    }
    
    // Delegator information
    struct Delegator {
        address delegateAddress;
        uint256 bondedAmount;
        uint256 startRound;
        uint256 withdrawRound;
    }
    
    // Validator information
    struct Validator {
        uint256 totalStake;
        uint256 commissionRate;
        bool isActive;
        uint256 rewardPool;
    }
    
    // State variables
    mapping(address => Delegator) public delegators;
    mapping(address => Validator) public validators;
    
    uint256 public currentRound;
    uint256 public constant MAX_COMMISSION = 10000;
    uint256 public constant MIN_DELEGATION = 1; // Vulnerability: Too low minimum
    bool public systemPaused;
    
    // Events
    event Bond(
        address indexed validator,
        address indexed previousValidator,
        address indexed delegator,
        uint256 amount,
        uint256 totalBonded
    );
    
    event Unbond(
        address indexed validator,
        address indexed delegator,
        uint256 amount
    );
    
    event ValidatorRegistered(
        address indexed validator,
        uint256 commissionRate
    );
    
    event DelegationBlocked(
        address indexed wouldBeValidator,
        address indexed intendedValidator,
        string reason
    );

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        currentRound = 1;
        systemPaused = false;
    }
    
    modifier whenNotPaused() {
        require(!systemPaused, "System is paused");
        _;
    }
    
    /**
     * @dev Register as a validator
     */
    function registerValidator(uint256 _commissionRate) external {
        require(_commissionRate <= MAX_COMMISSION, "Commission rate too high");
        
        Validator storage validator = validators[msg.sender];
        validator.commissionRate = _commissionRate;
        validator.isActive = true;
        
        emit ValidatorRegistered(msg.sender, _commissionRate);
    }
    
    /**
     * @dev Delegate tokens to a validator
     */
    function delegateStake(uint256 _amount, address _to) external whenNotPaused {
        _delegateStakeFor(_amount, msg.sender, _to);
    }
    
    /**
     * @dev Delegate tokens on behalf of another address 
     * @param _amount Amount to delegate  
     * @param _owner Address to delegate for
     * @param _to Validator to delegate to
     * 
     * @notice Vulnerability: This allows anyone to delegate on behalf of others
     *         without authorization
     */
    function delegateStakeFor(
        uint256 _amount,
        address _owner,
        address _to
    ) external whenNotPaused {
        // Vulnerability: No authorization check
        _delegateStakeFor(_amount, _owner, _to);
    }
    
    /**
     * @dev Internal delegation logic
     */
    function _delegateStakeFor(
        uint256 _amount,
        address _owner,
        address _to
    ) internal {
        require(_amount >= MIN_DELEGATION, "Amount too small");
        require(_to != address(0), "Invalid validator address");
        
        Delegator storage delegator = delegators[_owner];
        uint256 currentBondedAmount = delegator.bondedAmount;
        address currentDelegate = delegator.delegateAddress;
        
        // Handle delegation scenarios
        if (getDelegatorStatus(_owner) == DelegatorStatus.Unbonded) {
            delegator.startRound = currentRound + 1;
        } else if (currentBondedAmount > 0 && currentDelegate != _to) {
            // VULNERABILITY: This check prevents validators from delegating to others
            require(
                !isRegisteredValidator(_owner),
                "Registered validators cannot delegate to other addresses"
            );
            
            _decreaseValidatorStake(currentDelegate, currentBondedAmount);
            delegator.startRound = currentRound + 1;
        }
        
        // Update delegator state
        delegator.delegateAddress = _to;
        delegator.bondedAmount = currentBondedAmount + _amount;
        
        // Update validator stake
        _increaseValidatorStake(_to, currentBondedAmount + _amount);
        
        // Transfer tokens
        if (_amount > 0) {
            require(
                stakingToken.transferFrom(msg.sender, address(this), _amount),
                "Token transfer failed"
            );
        }
        
        emit Bond(_to, currentDelegate, _owner, _amount, delegator.bondedAmount);
        
        // Autoregister as validator if self delegating
        if (_owner == _to && currentBondedAmount == 0) {
            validators[_owner].isActive = true;
            emit ValidatorRegistered(_owner, 0);
        }
    }
    
    /**
     * @dev Check if an address is a registered validator
     * @param _validator Address to check
     * @return bool Whether the address is a validator
     * 
     * @notice Vulnerability: A user becomes a validator with any self delegation amount
     */
    function isRegisteredValidator(address _validator) public view returns (bool) {
        Delegator storage d = delegators[_validator];
        return d.delegateAddress == _validator && d.bondedAmount > 0;
    }
    
    /**
     * @dev Get delegator status
     */
    function getDelegatorStatus(address _delegator) public view returns (DelegatorStatus) {
        Delegator storage d = delegators[_delegator];
        
        if (d.bondedAmount == 0) {
            return DelegatorStatus.Unbonded;
        }
        
        return DelegatorStatus.Bonded;
    }
    
    /**
     * @dev Undelegate tokens
     */
    function undelegateStake(uint256 _amount) external {
        Delegator storage delegator = delegators[msg.sender];
        require(delegator.bondedAmount >= _amount, "Insufficient bonded amount");
        
        address currentDelegate = delegator.delegateAddress;
        
        delegator.bondedAmount -= _amount;
        delegator.withdrawRound = currentRound + 7;
        
        _decreaseValidatorStake(currentDelegate, _amount);
        
        emit Unbond(currentDelegate, msg.sender, _amount);
    }
    
    /**
     * @dev Withdraw undelegated tokens
     */
    function withdrawStake() external {
        Delegator storage delegator = delegators[msg.sender];
        require(delegator.withdrawRound <= currentRound, "Withdrawal not available yet");
        require(delegator.bondedAmount == 0, "Must undelegate all tokens first");
        
        uint256 withdrawAmount = delegator.bondedAmount;
        
        require(
            stakingToken.transfer(msg.sender, withdrawAmount),
            "Token transfer failed"
        );
    }
    
    /**
     * @dev Preview delegation
     */
    function previewDelegation(address _owner, address _to) 
        external view returns (bool canDelegate, string memory reason) {
        
        Delegator storage delegator = delegators[_owner];
        uint256 currentBondedAmount = delegator.bondedAmount;
        address currentDelegate = delegator.delegateAddress;
        
        if (currentBondedAmount > 0 && currentDelegate != _to) {
            if (isRegisteredValidator(_owner)) {
                return (false, "Registered validators cannot delegate to other addresses");
            }
        }
        
        return (true, "Delegation would succeed");
    }
    
    /**
     * @dev Direct grief attack function for demonstration
     */
    function griefAttack(address _victim) external whenNotPaused {
        require(stakingToken.balanceOf(msg.sender) >= 1, "Need at least 1 wei");
        require(!isRegisteredValidator(_victim), "Target is already a validator");
        
        this.delegateStakeFor(1, _victim, _victim);
        
        emit DelegationBlocked(_victim, _victim, "Victim forced to become validator");
    }
    
    /**
     * @dev Increase validator stake
     */
    function _increaseValidatorStake(address _validator, uint256 _amount) internal {
        validators[_validator].totalStake += _amount;
    }
    
    /**
     * @dev Decrease validator stake
     */
    function _decreaseValidatorStake(address _validator, uint256 _amount) internal {
        validators[_validator].totalStake -= _amount;
    }
    
    /**
     * @dev Admin functions
     */
    function advanceRound() external onlyOwner {
        currentRound += 1;
    }
    
    function pauseSystem() external onlyOwner {
        systemPaused = true;
    }
    
    function unpauseSystem() external onlyOwner {
        systemPaused = false;
    }
    
    function getValidatorInfo(address _validator) 
        external view returns (uint256 totalStake, uint256 commissionRate, bool isActive) {
        Validator storage v = validators[_validator];
        return (v.totalStake, v.commissionRate, v.isActive);
    }
}

/**
 * @title MockStakingToken
 * @dev Simple ERC20 token for testing
 */
contract MockStakingToken is ERC20 {
    constructor() ERC20("Staking Token", "STAKE") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
