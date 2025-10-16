// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "/lib/reactive-lib/src/interfaces/IReactive.sol";
import "/lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";

contract TWAPOrderReactive is IReactive, AbstractPausableReactive {
    
    event TWAPExecutionTriggered(uint256 indexed orderId, uint256 executionNumber);
    event TWAPOrderFinished(uint256 indexed orderId);
    
    // Sepolia Chain ID where DEX and TWAP contracts are deployed
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;
    
    // Event topic hashes from TWAPOrderCallback contract
    uint256 private constant TWAP_ORDER_EXECUTED_TOPIC_0 = 0xbf1678f63592cf78697cd879276fdf3025d241a4144d5d7750cb82ace684df00;
    uint256 private constant TWAP_ORDER_COMPLETED_TOPIC_0 = 0x009dd495421195eba11b580b9afa14d538b352941c8a9626a2a529f3066294e1;
    uint256 private constant TWAP_ORDER_FAILED_TOPIC_0 = 0xf2af3527ff84738fc93c9f0422e506486f8bae69e5a5a9b245b04a54b0492402;
    
    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;
    
    // Order state (reactive contract is deployed per order)
    address private twapCallbackContract;
    uint256 private orderId;
    uint256 public cronTopic;
    uint256 private maxExecutions;
    uint256 private currentExecution;
    bool private orderActive;
    
    constructor(
        address _twapCallbackContract,
        address _service,
        uint256 _orderId,
        uint256 _cronInterval, // 0=Cron1(7s), 1=Cron10(1minute), 2=Cron100(12minutes), 3=Cron1000(2hours), 4=Cron10000(28hours)
        uint256 _maxExecutions
    ) payable {
        service = ISystemContract(payable(_service));
        twapCallbackContract = _twapCallbackContract;
        orderId = _orderId;
        maxExecutions = _maxExecutions;
        currentExecution = 0;
        orderActive = true;
        
        // Set cron topic based on interval from the provided table
        if (_cronInterval == 0) {
            cronTopic = 0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514; // Cron1 - every block (~7s)
        } else if (_cronInterval == 1) {
            cronTopic = 0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687; // Cron10 - ~1 minute
        } else if (_cronInterval == 2) {
            cronTopic = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70; // Cron100 - ~12 minutes
        } else if (_cronInterval == 3) {
            cronTopic = 0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4; // Cron1000 - ~2 hours
        } else if (_cronInterval == 4) {
            cronTopic = 0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56; // Cron10000 - ~28 hours
        } else {
            revert("Invalid cron interval");
        }
        
        if (!vm) {
            // Subscribe to cron events for timing
            service.subscribe(
                block.chainid, // Lasna testnet chain ID
                address(service),
                cronTopic,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            
            // Subscribe to TWAP callback events on Sepolia to track order status
            service.subscribe(
                SEPOLIA_CHAIN_ID,
                twapCallbackContract,
                TWAP_ORDER_EXECUTED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            
            service.subscribe(
                SEPOLIA_CHAIN_ID,
                twapCallbackContract,
                TWAP_ORDER_COMPLETED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            
            service.subscribe(
                SEPOLIA_CHAIN_ID,
                twapCallbackContract,
                TWAP_ORDER_FAILED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }
    
    function getPausableSubscriptions() internal view override returns (Subscription[] memory) {
        Subscription[] memory result = new Subscription[](1);
        result[0] = Subscription(
            block.chainid, // Lasna testnet
            address(service),
            cronTopic,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }
    
    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == cronTopic) {
            // Cron event triggered - time to execute TWAP order
            if (!orderActive || currentExecution >= maxExecutions) {
                return;
            }
            
            // Send callback to Sepolia to execute TWAP order
            bytes memory payload = abi.encodeWithSignature(
                "executeTWAPOrder(address,uint256)",
                address(0), // sender placeholder
                orderId
            );
            
            emit TWAPExecutionTriggered(orderId, currentExecution + 1);
            
            emit Callback(
                SEPOLIA_CHAIN_ID,
                twapCallbackContract,
                CALLBACK_GAS_LIMIT,
                payload
            );
            
        } else if (log._contract == twapCallbackContract && log.topic_0 == TWAP_ORDER_EXECUTED_TOPIC_0) {
            // TWAP order was executed successfully on Sepolia
            // Extract orderId from topic_1 (indexed parameter)
            uint256 eventOrderId = uint256(log.topic_1);
            
            if (eventOrderId == orderId) {
                currentExecution++;
                
                if (currentExecution >= maxExecutions) {
                    orderActive = false;
                    emit TWAPOrderFinished(orderId);
                }
            }
            
        } else if (log._contract == twapCallbackContract && 
                  (log.topic_0 == TWAP_ORDER_COMPLETED_TOPIC_0 || log.topic_0 == TWAP_ORDER_FAILED_TOPIC_0)) {
            // TWAP order was completed or failed on Sepolia
            // Extract orderId from topic_1 (indexed parameter)
            uint256 eventOrderId = uint256(log.topic_1);
            
            if (eventOrderId == orderId) {
                orderActive = false;
                emit TWAPOrderFinished(orderId);
            }
        }
    }
    
    // View function to check order status
    function getOrderStatus() external view returns (
        uint256 _orderId,
        uint256 _currentExecution,
        uint256 _maxExecutions,
        bool _orderActive
    ) {
        return (orderId, currentExecution, maxExecutions, orderActive);
    }
}