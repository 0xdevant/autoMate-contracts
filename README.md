## AutoMate - Hookathon Project for Uniswap Hook Incubator(UHI)

This project is submitted as the Capstone Project to apply for the 1st Cohort of the UHI program's Hookathon.

AutoMate is a general-purpose hook to let users put up a bounty and subscribe to an automatic on-chain task execution service running by a
network of keepers(a.k.a. the swappers). Keepers are incentivized to execute the task as closely to the scheduled execution time as possible in
order to claim the maximum amount of bounty.

## Team Formation

[Me](https://twitter.com/0xDevAnt) and [Gareth](https://x.com/felixtam15)

## Contract Structure

AutoMate mainly consists of two contracts:

`AutoMate.sol` - The Hub that handles all the subscriptions and executions of on-chain tasks.

`AutoMateHook.sol` - The Uniswap v4 Hook that triggers the task execution during every swap.

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

1. A frontend to allow task subscription and displaying all the bounties available with a swap UI
2. Apply gas simulation and security check to the calldata users passed in while subscribing tasks to prevent spam/malicious task subscription
3. Allow recurring-task subscription

## References

This idea was first thought of integrating with Eigen Layer's AVS, but it becomes more economically viable thanks to the inspiration from
[UniBrain Hook](https://hackmd.io/@kames/unibrain-hook).

## Remarks

Due to time restrictions, this idea was revamped into a more minimal version. Please refer to the
[.archive](https://github.com/0xdevant/autoMate-contracts/tree/main/.archive) folder if you want to check on the original implementation of the
hook.
