## AutoMate - Hookathon Project for Uniswap Hook Incubator(UHI)

This project is submitted as the Capstone Project to apply for the 1st Cohort of the UHI program's Hookathon.

AutoMate is a general-purpose hook to let users subscribe to a service running by a network of decentralized keepers(a.k.a. the swappers) for automatic execution of on-chain tasks. Keepers are incentivized by swapping at a favorable price curve adjusted dynamically via Dutch Auction to help subscribers execute any on-chain tasks in a trustless way.

## Team Formation

[Me](https://twitter.com/0xDevAnt) and [Gareth](https://x.com/felixtam15)

## Contract Structure

AutoMate mainly consists of two contracts:

`AutoMate.sol` - The Hub that handles all the subscriptions and executions of on-chain tasks.

`AutoMateHook.sol` - The Uniswap v4 Hook that implements the custom price curve w/ Dutch auction to incentivize keepers to execute tasks.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## Future Improvements

1. A frontend to allow task subscription and displaying the dynamic price curve with a swap UI
2. Apply gas simulation and security check to the calldata users passed in while subscribing tasks to prevent spam/malicious task subscription
3. Allow hooks to accept a looser interval (allow tasks to be scheduled per 2hr, 4day, 3week…)
4. Automatically compound the fees taken from users' subscription into discounted pools as liquidity to smoothen the balance between Token A and Token B

## References

This idea was first thought of integrating with Eigen Layer's AVS, but it becomes more economically viable thanks to the inspiration from [UniBrain Hook](https://hackmd.io/@kames/unibrain-hook).
