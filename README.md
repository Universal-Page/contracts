# Universal Page Contracts

![test](https://github.com/Universal-Page/contracts/actions/workflows/test.yml/badge.svg)

| network | contract / library    | address                                    |
| ------- | --------------------- | ------------------------------------------ |
| mainnet | PageName              |                                            |
| mainnet | GenesisDigitalAsset   |                                            |
| mainnet | Participant           |                                            |
| mainnet | LSP7Listings          |                                            |
| mainnet | LSP7Offers            |                                            |
| mainnet | LSP7Marketplace       |                                            |
| mainnet | LSP8Listings          |                                            |
| mainnet | LSP8Offers            |                                            |
| mainnet | LSP8Auctions          |                                            |
| mainnet | LSP8Marketplace       |                                            |
| mainnet | Points                |                                            |
| mainnet | Royalties             |                                            |
| testnet | PageName              | 0x8b08eeb9183081de7e2d4ae49fad4afb56e31ab4 |
| testnet | GenesisDigitalAsset   | 0x86488e1c57115f6a7cad26a4f83367cb1e117911 |
| testnet | CollectorDigitalAsset | 0x9eb7a7666fc33e7a68a061ac6de2e239f865658b |
| testnet | Participant           | 0x5a485297a1b909032a6b7000354f3322047028ee |
| testnet | LSP7Listings          | 0x44cd7d06ceb509370b75e426ea3c12824a665e36 |
| testnet | LSP7Offers            | 0xdf9defd55365b7b073cae009cf53dd830902c5a7 |
| testnet | LSP7Marketplace       | 0xc9c940a35fc8d3522085b991ce3e1a920354f19a |
| testnet | LSP8Listings          | 0xf069f9b8e0f96d742c6dfd3d78b0e382f3411207 |
| testnet | LSP8Offers            | 0xaebcc2c80abacb7e4d928d4c0a52c7bbeba4c4be |
| testnet | LSP8Auctions          | 0x39456bcd4d450e55f851f97c30df828a4e1f6c66 |
| testnet | LSP8Marketplace       | 0xe9f0feab3d50ccbe40d99f669fe1e89172908cdf |
| testnet | Points                | 0x3582f474F6E9FB087651b135d6224500A89e6f44 |
| testnet | Royalties             | 0x1c51619209EFE37C759e4a9Ca91F1e68A96E19E3 |

## Development

Start local node: `./tools/local_network.sh` and verify deployment locally:

```
./tools/deploy.sh --libraries --target local
./tools/deploy.sh --script marketplace/Participant.s.sol --target local --broadcast
```

## Analyze

Run `slither` by `slither . --triage-mode`.

## Deploy

```
./tools/deploy.sh --script page/PageName.s.sol --target testnet --broadcast
```

## Configure

```
 ./tools/configure.sh --script page/PageName.s.sol --target testnet --profile --broadcast
```

## Export

```
 ./tools/artifacts.sh --target testnet
```

## Publish

Publishes functon selectors and source code on blockscout

```
./tools/submit_selectors.sh --target testnet
./tools/verify.sh --target testnet
```

## License

See [LGPL-2.1 license](LICENSE)
