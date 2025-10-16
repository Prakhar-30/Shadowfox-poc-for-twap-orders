// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '/lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import '/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

interface ISimpleDEX {
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}

contract TWAPOrderCallback is AbstractCallback {
    
    struct TWAPOrder {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 totalAmountIn;
        uint256 amountPerExecution;
        uint256 executedAmount;
        uint256 executionCount;
        uint256 maxExecutions;
        bool isActive;
    }
    
    event TWAPOrderCreated(
        uint256 indexed orderId,
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 totalAmount,
        uint256 amountPerExecution,
        uint256 maxExecutions
    );
    
    event TWAPOrderExecuted(
        uint256 indexed orderId,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionNumber
    );
    
    event TWAPOrderCompleted(
        uint256 indexed orderId,
        address indexed user
    );
    
    event TWAPOrderFailed(
        uint256 indexed orderId,
        address indexed user,
        string reason
    );
    
    ISimpleDEX public dex;
    uint256 public nextOrderId;
    mapping(uint256 => TWAPOrder) public orders;
    
    constructor(
        address _callback_sender,
        address _dex
    ) AbstractCallback(_callback_sender) payable {
        dex = ISimpleDEX(_dex);
        nextOrderId = 1;
    }
    
    // Create a new TWAP order
    function createTWAPOrder(
        address tokenIn,
        address tokenOut,
        uint256 totalAmountIn,
        uint256 maxExecutions
    ) external returns (uint256 orderId) {
        require(totalAmountIn > 0, "Total amount must be greater than 0");
        require(maxExecutions > 0, "Max executions must be greater than 0");
        require(totalAmountIn % maxExecutions == 0, "Total amount must be divisible by max executions");
        
        uint256 amountPerExecution = totalAmountIn / maxExecutions;
        
        // Transfer total amount from user
        IERC20(tokenIn).transferFrom(msg.sender, address(this), totalAmountIn);
        
        orderId = nextOrderId++;
        
        orders[orderId] = TWAPOrder({
            user: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            totalAmountIn: totalAmountIn,
            amountPerExecution: amountPerExecution,
            executedAmount: 0,
            executionCount: 0,
            maxExecutions: maxExecutions,
            isActive: true
        });
        
        emit TWAPOrderCreated(
            orderId,
            msg.sender,
            tokenIn,
            tokenOut,
            totalAmountIn,
            amountPerExecution,
            maxExecutions
        );
        
        return orderId;
    }
    
    // Execute TWAP order (called by reactive contract via callback)
    function executeTWAPOrder(
        address /* sender */,
        uint256 orderId
    ) external authorizedSenderOnly {
        TWAPOrder storage order = orders[orderId];
        
        require(order.isActive, "Order is not active");
        require(order.executionCount < order.maxExecutions, "Order already completed");
        
        try this._executeSwap(orderId) returns (uint256 amountOut) {
            order.executedAmount += order.amountPerExecution;
            order.executionCount++;
            
            emit TWAPOrderExecuted(
                orderId,
                order.user,
                order.amountPerExecution,
                amountOut,
                order.executionCount
            );
            
            // Check if order is completed
            if (order.executionCount >= order.maxExecutions) {
                order.isActive = false;
                emit TWAPOrderCompleted(orderId, order.user);
            }
        } catch Error(string memory reason) {
            // Mark order as failed
            order.isActive = false;
            
            // Refund remaining tokens to user
            uint256 remainingAmount = order.totalAmountIn - order.executedAmount;
            if (remainingAmount > 0) {
                IERC20(order.tokenIn).transfer(order.user, remainingAmount);
            }
            
            emit TWAPOrderFailed(orderId, order.user, reason);
        } catch {
            // Mark order as failed
            order.isActive = false;
            
            // Refund remaining tokens to user
            uint256 remainingAmount = order.totalAmountIn - order.executedAmount;
            if (remainingAmount > 0) {
                IERC20(order.tokenIn).transfer(order.user, remainingAmount);
            }
            
            emit TWAPOrderFailed(orderId, order.user, "Unknown error");
        }
    }
    
    function _executeSwap(uint256 orderId) external returns (uint256) {
        require(msg.sender == address(this), "Internal function");
        
        TWAPOrder storage order = orders[orderId];
        
        // Approve DEX to spend tokens
        IERC20(order.tokenIn).approve(address(dex), order.amountPerExecution);
        
        // Execute swap
        uint256 amountOut = dex.swapTokens(
            order.tokenIn,
            order.tokenOut,
            order.amountPerExecution
        );
        
        // Transfer output tokens to user
        IERC20(order.tokenOut).transfer(order.user, amountOut);
        
        return amountOut;
    }
    
    // Cancel TWAP order (only by user)
    function cancelTWAPOrder(uint256 orderId) external {
        TWAPOrder storage order = orders[orderId];
        
        require(order.user == msg.sender, "Not authorized");
        require(order.isActive, "Order is not active");
        
        order.isActive = false;
        
        // Refund remaining tokens
        uint256 remainingAmount = order.totalAmountIn - order.executedAmount;
        if (remainingAmount > 0) {
            IERC20(order.tokenIn).transfer(order.user, remainingAmount);
        }
        
        emit TWAPOrderCompleted(orderId, order.user);
    }
}