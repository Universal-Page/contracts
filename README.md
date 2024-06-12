# Universal Page Contracts

[![test](https://github.com/Universal-Page/contracts/actions/workflows/test.yml/badge.svg)](https://github.com/Universal-Page/contracts/actions/workflows/test.yml)
[![analyze](https://github.com/Universal-Page/contracts/actions/workflows/analyze.yaml/badge.svg)](https://github.com/Universal-Page/contracts/actions/workflows/analyze.yaml)

| network | contract / library    | address                                    |
| ------- | --------------------- | ------------------------------------------ |
| base-sepolia | Points                | 0xa29aeaabb5DA0CC3635576933a66c1B714f058C1 |
| base-sepolia | Royalties             | 0x7D6DA08a9d13cEC8649215F8bbD9dcA101c22659 |
| base-sepolia | ProfilesReverseLookup | 0x3582f474f6e9fb087651b135d6224500a89e6f44 |
| lukso | PageName              | 0x39456bcd4d450e55f851f97c30df828a4e1f6c66 |
| lukso | GenesisDigitalAsset   | 0x8da488c29fb873c9561ccf5ff44dda6c1deddc37 |
| lukso | CollectorDigitalAsset | 0x5599d0ae8576250db2b9a9975fd3db1f6399b4fd |
| lukso | Participant           | 0xa29aeaabb5da0cc3635576933a66c1b714f058c1 |
| lukso | LSP7Listings          | 0xe7f5c709d62bcc3701f4c0cb871eb77e301283b5 |
| lukso | LSP7Offers            | 0xb2379f3f3c623cd2ed18e97e407cdda8fe6c6da6 |
| lukso | LSP7Orders            | 0x07d815d546072547471d9cde244367d274268b35 |
| lukso | LSP7Marketplace       | 0xe04cf97440cd191096c4103f9c48abd96184fb8d |
| lukso | LSP8Listings          | 0x4faab47b234c7f5da411429ee86cb15cb0754354 |
| lukso | LSP8Offers            | 0xed189b51455c9714aa49b0c55529469c512b10b6 |
| lukso | LSP8Auctions          | 0x6eee8a19198bf39f2cefc24713acbdcc3c016dec |
| lukso | LSP8Marketplace       | 0x6807c995602eaf523a95a6b97acc4da0d3894655 |
| lukso | Points                | 0x157668416776c78EaB825D0d3969d75DC7dD7C0D |
| lukso | Royalties             | 0x391B24e80d85587C1cb698f0cD7Dfb7191D6875F |
| lukso | Vault                 | 0xa5b37d755b97c272853b9726c905414706a0553a |
| lukso | Elections             | 0xd813fd267a5d3d10adbe9d22ba6dc7fda2ddf517 |
| lukso | ProfilesOracle        | 0x482a6fd801fe3290a49e465c168ad9f8772b8d7e |
| lukso | ProfilesReverseLookup | 0xa0eb05c666fcf6cbeca77e14ec43cb5d5a852601 |
| lukso-testnet | PageName              | 0x8b08eeb9183081de7e2d4ae49fad4afb56e31ab4 |
| lukso-testnet | GenesisDigitalAsset   | 0xc06bcd7a286308861bd99da220acbc8901949fbd |
| lukso-testnet | CollectorDigitalAsset | 0x2eef6216274bf0ede21a8a55cbb5b896bb82ac8b |
| lukso-testnet | Participant           | 0x5a485297a1b909032a6b7000354f3322047028ee |
| lukso-testnet | LSP7Listings          | 0xf3a20e7bc566940ed1e707c6d7d05497cf6527f1 |
| lukso-testnet | LSP7Offers            | 0x8f69db0bc0a1d156210259a154b73b7aa63f4631 |
| lukso-testnet | LSP7Orders            | 0x80e62ece29d2ae6a7fec34db5a9cefe4e34f40a9 |
| lukso-testnet | LSP7Marketplace       | 0x61c3dd3476a88de7a2bae7e2bc55889185faea1e |
| lukso-testnet | LSP8Listings          | 0x1dabeddbc94847b4ca9027073e545f67917a84f6 |
| lukso-testnet | LSP8Offers            | 0x84c0b26747a4f997ab1bfe5110a9579de2c0aeaf |
| lukso-testnet | LSP8Auctions          | 0xb20f814e55720e477640717bfbc139cf663e1ab4 |
| lukso-testnet | LSP8Marketplace       | 0x6364738eb197115aece87591dff51d554535d1f8 |
| lukso-testnet | Points                | 0x3582f474F6E9FB087651b135d6224500A89e6f44 |
| lukso-testnet | Royalties             | 0x1c51619209EFE37C759e4a9Ca91F1e68A96E19E3 |
| lukso-testnet | Elections             | 0xbe69df047c7e10766cbe5e8bd2fac3dc18a9b745 |
| lukso-testnet | ProfilesReverseLookup | 0x953eef8151770c4cc60ec27468acee85eb8d81f8 |

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
