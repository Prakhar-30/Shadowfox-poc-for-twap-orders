// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract SimpleDEX {
    
    event TokenSwapped(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    // Mapping from token pair to exchange rate (tokenA -> tokenB)
    // Rate is in basis points, 10000 = 1:1
    mapping(address => mapping(address => uint256)) public exchangeRates;
    
    // Mapping to track liquidity for each token
    mapping(address => uint256) public liquidity;
    
    // Set exchange rate between two tokens
    function setExchangeRate(address tokenA, address tokenB, uint256 rate) external {
        exchangeRates[tokenA][tokenB] = rate;
    }
    
    // Add liquidity to the DEX
    function addLiquidity(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        liquidity[token] += amount;
    }
    
    // Swap tokens
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be greater than 0");
        require(exchangeRates[tokenIn][tokenOut] > 0, "Exchange rate not set");
        
        // Calculate output amount
        amountOut = (amountIn * exchangeRates[tokenIn][tokenOut]) / 10000;
        
        require(liquidity[tokenOut] >= amountOut, "Insufficient liquidity");
        
        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        // Update liquidity
        liquidity[tokenIn] += amountIn;
        liquidity[tokenOut] -= amountOut;
        
        emit TokenSwapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        
        return amountOut;
    }
    
    // Get quote for swap
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        require(exchangeRates[tokenIn][tokenOut] > 0, "Exchange rate not set");
        amountOut = (amountIn * exchangeRates[tokenIn][tokenOut]) / 10000;
        return amountOut;
    }
}