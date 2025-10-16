# TWAP Order System Demo

## Overview

The **TWAP Order System Demo** implements a reactive smart contract system that enables users to execute Time-Weighted Average Price (TWAP) orders across decentralized exchanges. Users can pre-approve a total amount of tokens and have the system automatically execute smaller trades at regular intervals until the full amount is spent. This demo demonstrates how reactive smart contracts can provide automated trading strategies for DeFi protocols.

## Contracts

**Reactive Contract**: [TWAPOrderReactive](./TWAPOrderReactive.sol) subscribes to CRON events to periodically execute TWAP orders and to order status events from the callback contract. When triggered by a CRON event, it sends a callback to execute the next portion of the TWAP order. The contract tracks execution progress and automatically stops when the maximum number of executions is reached or the order is completed/cancelled.

**Origin/Destination Chain Contract**: [TWAPOrderCallback](./TWAPOrderCallback.sol) manages TWAP orders and executes token swaps. When triggered by the Reactive Network, it verifies the caller, executes a swap for the predetermined amount through the DEX, transfers output tokens to the user, and updates order status. The contract emits `TWAPOrderExecuted` events on successful swaps or `TWAPOrderFailed` events with reasons on failure.

**DEX Contract**: [SimpleDEX](./SimpleDEX.sol) provides basic decentralized exchange functionality with fixed exchange rates. It handles token swaps, liquidity management, and maintains exchange rate mappings between token pairs.



## Deployment & Testing

### Environment Variables

Before proceeding further, configure these environment variables:

* `SEPOLIA_RPC` — RPC URL for Sepolia testnet where DEX and callback contracts are deployed.
* `PRIVATE_KEY` — Private key for signing transactions on Sepolia testnet.
* `LASNA_RPC` — RPC URL for the Reactive Network (Lasna testnet).
* `PRIVATE_KEY` — Private key for signing transactions on the Reactive Network.
* `DESTINATION_CALLBACK_PROXY_ADDR` — The service address on Sepolia (see [Reactive Docs](https://dev.reactive.network/origins-and-destinations#callback-proxy-address)).
* `SYSTEM_CONTRACT_ADDR` — The service address on the Reactive Network (see [Reactive Docs](https://dev.reactive.network/reactive-mainnet#overview)).
* `CRON_TOPIC` — An event enabling time-based automation at fixed block intervals (see [Reactive Docs](https://dev.reactive.network/reactive-library#cron-functionality)).

> ℹ️ **Reactive Faucet on Sepolia**  
> To receive testnet REACT, send SepETH to the Reactive faucet contract on Ethereum Sepolia: `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`. The factor is 1/5, meaning you get 5 REACT for every 1 SepETH sent.

> ⚠️ **Broadcast Error**  
> If you see the following message: `error: unexpected argument '--broadcast' found`, it means your Foundry version (or local setup) does not support the `--broadcast` flag for `forge create`. Simply remove `--broadcast` from your command and re-run it.

### Step 1 — Token Configuration

Export the token addresses for USDC and SEPO:

```bash
export TOKEN_IN=0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8   # USDC token address
export TOKEN_OUT=0x642037396D62891302f06dDE0bc21071834A0260  # SEPO token address
```

### Step 2 — TWAP Order Parameters

Define TWAP order parameters for $100 USDC → SEPO over 5 minutes:

```bash
export TOTAL_AMOUNT=100000000        # 100 USDC (6 decimals)
export MAX_EXECUTIONS=5             # 5 executions over 5 minutes
export CRON_INTERVAL=1               # Every 10 blocks (~1 minute)
```

### Step 3 — Deploy DEX Contract

Deploy the SimpleDEX contract on Sepolia. Assign the `Deployed to` address from the response to `DEX_ADDR`:

```bash
forge create --broadcast --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY SimpleDEX.sol:SimpleDEX
```

### Step 4 — Deploy Callback Contract

Deploy the TWAP callback contract on Sepolia. Assign the `Deployed to` address to `CALLBACK_ADDR`:

```bash
forge create --broadcast --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY TWAPOrderCallback.sol:TWAPOrderCallback --constructor-args $SEPOLIA_PROXY $DEX_ADDR
```

### Step 5 — Configure DEX

Set exchange rates and add liquidity to the DEX:

```bash
# Set exchange rate (example: 1 USDC = 2.5 SEPO, rate in basis points)
cast send $DEX_ADDR 'setExchangeRate(address,address,uint256)' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $TOKEN_IN $TOKEN_OUT 250000000000000000

# Add liquidity for SEPO (assuming 18 decimals, adding 10,000 SEPO)

cast send $TOKEN_OUT "approve(address,uint256)" --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $DEX_ADDR 10000000000000000000000

cast send $DEX_ADDR 'addLiquidity(address,uint256)' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $TOKEN_OUT 10000000000000000000000
```

### Step 6 — Create TWAP Order

Approve tokens and create a TWAP order:

```bash
# Approve callback contract to spend your tokens
cast send $TOKEN_IN 'approve(address,uint256)' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $CALLBACK_ADDR $TOTAL_AMOUNT

# Create TWAP order and note the returned order ID
cast send $CALLBACK_ADDR 'createTWAPOrder(address,address,uint256,uint256)' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $TOKEN_IN $TOKEN_OUT $TOTAL_AMOUNT $MAX_EXECUTIONS
```

### Step 7 — Deploy Reactive Contract

Deploy the reactive contract on Lasna testnet using the order ID from step 6:

```bash
export ORDER_ID=1  # Use the actual order ID returned from step 6

forge create --legacy --broadcast --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY TWAPOrderReactive.sol:TWAPOrderReactive --value 1ether --constructor-args $CALLBACK_ADDR $SYSTEM_CONTRACT_ADDR $ORDER_ID $CRON_INTERVAL $MAX_EXECUTIONS
```

### Step 8 — Monitor Execution

The reactive contract will automatically execute the TWAP order based on the configured CRON interval. You can monitor:

- Order execution events on [Sepolia Etherscan](https://sepolia.etherscan.io/)
- Reactive contract status on Lasna testnet explorer
- Your token balances to track swap progress

### Step 9 — Cancel Order (Optional)

Users can cancel active orders to get refunds of unexecuted amounts:

```bash
cast send $CALLBACK_ADDR 'cancelTWAPOrder(uint256)' --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY $ORDER_ID
```

### Step 10 — Pause/Resume Reactive Contract (Optional)

To pause the reactive contract monitoring:

```bash
cast send --legacy $REACTIVE_ADDR "pause()" --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY
```

To resume:

```bash
cast send --legacy $REACTIVE_ADDR "resume()" --rpc-url $LASNA_RPC --private-key $PRIVATE_KEY
```

## CRON Intervals Available

- **0**: Every block (~7 seconds) - for testing only
- **1**: Every 10 blocks (~1 minute) - frequent trading
- **2**: Every 100 blocks (~12 minutes) - regular trading  
- **3**: Every 1000 blocks (~2 hours) - slow DCA strategy
- **4**: Every 10000 blocks (~28 hours) - daily DCA strategy

## Example Usage Scenario

A user wants to buy SEPO tokens with $100 USDC over 20 minutes using 1-minute intervals:

1. **Total amount**: 100 USDC (100,000,000 with 6 decimals)
2. **Executions**: 20 (so $5 USDC per execution every minute)  
3. **Interval**: Every minute (CRON_INTERVAL=1, every 10 blocks)
4. **Duration**: 20 minutes total
5. **Result**: $5 worth of SEPO purchased every minute until $100 is spent

The system automatically handles the entire process, ensuring consistent execution without manual intervention.

## Proof of System Working

The TWAP order system has been successfully deployed and tested. You can verify the system's operation by examining the following contract interactions:

### Live Contract Addresses & Transaction History:

**SimpleDEX Contract (Sepolia)**:
- **Address**: [0x9A9538E2D88ddCD9b45Cfd53131eAdc93252A080](https://sepolia.etherscan.io/address/0x9A9538E2D88ddCD9b45Cfd53131eAdc93252A080#events)
- **Events**: Shows token swaps and liquidity operations

**TWAPOrderCallback Contract (Sepolia)**:
- **Address**: [0x540ca727475d46395184e8e5436154f89526d6d8](https://sepolia.etherscan.io/address/0x540ca727475d46395184e8e5436154f89526d6d8/advanced#events)
- **Events**: Shows TWAP order creation, execution, and completion events

**TWAPOrderReactive Contract (Lasna)**:
- **Address**: [0x49abe186a9b24f73e34ccae3d179299440c352ac](https://lasna.reactscan.net/address/0x49abe186a9b24f73e34ccae3d179299440c352ac/contract/0x0ab16de452e4cdd82f22968dc6abe160cda974d2?screen=transactions)
- **Transactions**: Shows reactive contract deployment and cross-chain callback executions
