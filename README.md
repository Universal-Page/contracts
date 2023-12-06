# Universal Page Contracts

![test](https://github.com/Universal-Page/contracts/actions/workflows/test.yml/badge.svg)

| network | contract / library    | address                                    |
| ------- | --------------------- | ------------------------------------------ |
| mainnet | PageName              | 0x39456bcd4d450e55f851f97c30df828a4e1f6c66 |
| mainnet | GenesisDigitalAsset   | 0x8da488c29fb873c9561ccf5ff44dda6c1deddc37 |
| testnet | CollectorDigitalAsset |                                            |
| mainnet | Participant           | 0xa29aeaabb5da0cc3635576933a66c1b714f058c1 |
| mainnet | LSP7Listings          | 0xe7f5c709d62bcc3701f4c0cb871eb77e301283b5 |
| mainnet | LSP7Offers            | 0xb2379f3f3c623cd2ed18e97e407cdda8fe6c6da6 |
| mainnet | LSP7Marketplace       | 0xe04cf97440cd191096c4103f9c48abd96184fb8d |
| mainnet | LSP8Listings          | 0x4faab47b234c7f5da411429ee86cb15cb0754354 |
| mainnet | LSP8Offers            | 0xed189b51455c9714aa49b0c55529469c512b10b6 |
| mainnet | LSP8Auctions          | 0x6eee8a19198bf39f2cefc24713acbdcc3c016dec |
| mainnet | LSP8Marketplace       | 0x6807c995602eaf523a95a6b97acc4da0d3894655 |
| mainnet | Points                | 0x157668416776c78EaB825D0d3969d75DC7dD7C0D |
| mainnet | Royalties             | 0x391B24e80d85587C1cb698f0cD7Dfb7191D6875F |
| testnet | PageName              | 0x288d83c922b2424dba195df40756b63f7cd9ef0d |
| testnet | GenesisDigitalAsset   | 0xc06bcd7a286308861bd99da220acbc8901949fbd |
| testnet | CollectorDigitalAsset |                                            |
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
