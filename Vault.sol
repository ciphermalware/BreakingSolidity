// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Pair.sol";

/// @title PairFactory
/// @notice Deploys and tracks Pair contracts for token trading pairs
contract PairFactory is Ownable {
    // token0 => token1 => pair address
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    address public feeRecipient;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    constructor(address _feeRecipient) {
        require(_feeRecipient != address(0), "PairFactory: zero fee recipient");
        feeRecipient = _feeRecipient;
    }

    /// @notice Creates a new Pair contract for the given token addresses
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "PairFactory: identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "PairFactory: zero address");
        require(getPair[token0][token1] == address(0), "PairFactory: pair exists");

        pair = address(new Pair(token0, token1, feeRecipient));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }

    /// @notice Returns the total number of pairs created
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Updates the fee recipient for newly created pairs
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "PairFactory: zero address");
        address old = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(old, _feeRecipient);
    }
}
