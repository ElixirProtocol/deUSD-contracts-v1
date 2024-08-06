<img align="right" width="150" height="150" top="100" style="border-radius:99%" src="https://i.imgur.com/H5aZQMA.jpg">

# Elixir deUSD Contracts • [![CI](https://github.com/ElixirProtocol/deUSD-contracts-v1/actions/workflows/test.yml/badge.svg)](https://github.com/ElixirProtocol/deUSD-contracts-v1/actions/workflows/test.yml)

## Background
This project contains the smart contracts for the Elixir Protocol’s deUSD.

v1 is based on Ethena’s minting contracts. v2 will be redesigned to enable further features such as permissionless mints/redemptions.

See the deUSD documentation for more information.

## Deployments

<table>
<tr>
<th>Network</th>
<th>deUSD</th>
<th>deUSDBalancerRateProvider</th>
<th>deUSDLPStaking</th>
<th>deUSDMinting</th>
<th>deUSDSilo</th>
<th>StakingRewardsDistributor</th>
<th>stdeUSD</th>
</tr>
<tr>
<td>Ethereum Mainnet (production)</td>
<td><code>0x15700B564Ca08D9439C58cA5053166E8317aa138</code></td>
<td><code>N/A</code></td>
<td><code>0xC7963974280261736868f962e3959Ee1E1B99712</code></td>
<td><code>0x69088d25a635D22dcbe7c4A5C7707B9cc64bD114</code></td>
<td><code>0x4595C32720718fe0E4047B2683E255515123148a</code></td>
<td><code>N/A</code></td>
<td><code>0x5C5b196aBE0d54485975D1Ec29617D42D9198326</code></td>
</tr>
</table>

## Usage

You will need a copy of [Foundry](https://github.com/foundry-rs/foundry) installed before proceeding. See the [installation guide](https://github.com/foundry-rs/foundry#installation) for details.

To build the contracts:

```sh
git clone https://github.com/ElixirProtocol/deUSD-contracts-v1.git
cd deUSD-contracts-v1
forge install
forge build
```

### Run Tests

In order to run unit tests, run:

```sh
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="deep" forge test
```

### Run Slither

After [installing Slither](https://github.com/crytic/slither#how-to-install), run:

```sh
slither src/
```

### Check coverage

To check the test coverage, run:

```sh
forge coverage
```

### Update Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

### Deploy Contracts

In order to deploy the contracts, set the relevant constants in the respective chain script, and run the following command(s):

```sh
forge script script/deploy/DeploySepolia.s.sol:DeploySepolia -vvvv --fork-url RPC --broadcast --slow
```
