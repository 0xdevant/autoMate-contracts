## AutoMate

A general-purpose hook to let user subscribe to a decentralized keeper service to help execute on-chain tasks automatically. Keepers are incentivized by swapping at a favorable price curve adjusted dynamically via Dutch Auction to help subscribers execute any on-chain tasks in a trustless way. Our demo use case would be a DCA task.

## Contract Structure

AutoMate mainly consists of two contracts:

`AutoMate.sol` - The Hub that handles all the subscriptions and executions of on-chain tasks.

`AutoMateHook.sol` - The Uniswap v4 Hook that implements the custom price curve w/ dutch auction to incentivize keepers to execute tasks.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## References

This idea was first thought of integrating with Eigen Layer's AVS, but it becomes more economically viable thanks to the inspiration from [UniBrain Hook](https://hackmd.io/@kames/unibrain-hook).
