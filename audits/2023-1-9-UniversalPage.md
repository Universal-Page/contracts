# Security Assessment

- Reviewer: UniversalPage
- Date: Jan 9th, 2023

## Executive Summary

This report was prepared for UniversalPage smart contracts in order to identify common issues and vulnerabilities in the source code. A comprehensive examination of the code was conducted using symbolic execution, static analysis, and manual code review.

The auditing process focuses on identifying attack vectors that pose the following risks:
- Loss of funds and/or NFTs by both UniversalPage and its customers
- Unauthorized access to change parameters and/or behavior of smart contracts

The security assessment found a range of issues, including critical and informational ones. The critical and major issues have been fixed and tested both in code and manually.

## Introduction

The review was performed on the following contracts:
| Contract | Description |
| - | - |
| LSP7CreatorDigitalAsset, LSP8CreatorIdentifiableDigitalAsset| Assets deployed by users on UniversalPage |
| LSP7DropDigitalAsset | LSP7 drop contract for explicitly listed accounts to claim preset number of tokens |
| Withdrawable | Enables contracts to accept and withdraw funds to a single beneficiary |
| ReentrancyGuard | Prevents reentrancy attack on set methods |
| LSP8FixedDropDigitalAsset | LSP8 asset with fixed parameters (price, limits, etc) enabling minting of tokens and collecting of proceeds |
| LSP7Listing, LSP8Listings | Marketplace contracts enabling users to manage listings |
| LSP8Offers, LSP8Offers | Marketplace contracts enabling users to make offers on listings |
| LSP8Auctions | Marketplace contract enabling users to manager auctions for listed assets |
| LSP7Marketplace, LSP8Marketplace | Marketplace contracts enabling users to transact by buying, accepting offers and auctions bids |
| Participant | Marketplace contract to tailor users transactions and experience |
| UniversalPageName | LSP8 asset representing unique page name on UniversalPage |
| UniversalPageNameController | Enforces controls on UniversalPageName tokens |
| PaymentProcessor | Facilitates explicit transfers between users |
| GenesisDigitalAsset | LSP7 asset representing attandance of UniversalPage mainnet launch |

## Methodology

The contracts have been assessed for common vulnerabilities such as reentrancy attacks, and access control. The code is modularized files being less than 200 lines. Functionality of the code has been verified through excessive unit and component testing. The following table shows the code coverage of critical contracts and components of the system:

| Contract | % Statements | % Branches | Functions |
| - | -: | -: | -: |
| ReentrancyGuard | 100 | 50 | 100 |
| Withdrawable | 100 | 58.33 | 100 |
| LSP8FixedDropDigitalAsset | 100 | 71.43 | 100 |
| LSP7Listings | 100 | 74.19 | 100 |
| LSP7Marketplace | 100 | 75 | 100 |
| LSP7Offers | 100 | 61.36 | 100 |
| LSP8Auctions | 100 | 59.68 | 85.71 |
| LSP8Listings | 100 | 75 | 100 |
| LSP8Marketplace | 97.22 | 73.33 | 87.5 |
| LSP8Offers | 100 | 62.5 | 100 |
| MarketplaceBase | 60.71 | 39.29 | 44.44 |
| MarketplaceModule | 93.75 | 62.5 | 90.91 |
| UniversalPageName | 95.83 | 68.75 | 87.5 |
| UniversalPageNameController | 100 | 82.76 | 100 |

Overall, including basic contracts and utilities: 87.85% statements are covered.

Additional security analysis tools have been applied:
- [Mythril](https://github.com/ConsenSys/mythril) - security analysis tool for EVM bytecode performs symbolic analysis.
- [Slither](https://github.com/crytic/slither) - security analysis tool to detect common valnurabilities and patterns.

## Findings

The tool analysis did not detect any major or critical issues. Some of results included: storage variables not being initialized, strict equality, reentrancy, and ignoring return values. All issues were manually reviewed and verified for correctness through unit tests.

The following contracts transact user and/or UniversalPage assets:
- LSP7DropDigitalAsset (funds/NFTs)
  - `claim` transfers N tokens from the contract. It verifies allowlist and whether tokens being claimed. This prevents unathorized claims and reentrancy.
  - `dispose` transfers all tokens from contract. It requires owner of the contract to call the method.
- LSP7Marketplace, LSP8Marketplace (funds/NFTs)
  - `buy` accepts funds and verifies number of tokens and total price. Retains fee amount in the contract, pays out royalties and seller amounts. Verifies exact total paid by buyer. Transfers paid number of tokens to the buyer. Prevents reentrancy.
  - `acceptOffer` closes offer and receives offer balance. Retains fee amount in the contract, pays out royalties and seller amounts. Verifies exact total paid by buyer. Transfers paid number of tokens to the buyer. Prevents reentrancy.
- LSP8Marketplace (funds/NFTs)
  - `acceptHighestBid` verifies auction is accepted by auction creator. Checks for highest bid, verifies bid's listing, auction, buyer, and receives bid balance. Retains fee amount in the contract, pays out royalties and seller amounts. Verifies exact total paid by buyer. Transfers paid number of tokens to the buyer. Prevents reentrancy.
- LSP8FixedDropDigitalAsset (funds)
  - `mint` accepts funds, mints, and transfers tokens. Prevents a high level of bot attacks, multi mints, checks funds according to a price, records balances for owner and UniversalPage. 
  - `claim` withdraws funds from the contract. Checks requester's balances, and prevents reentrancy.
- LSP7Offers, LSP8Offers (funds)
  - `makeOffer` accepts funds per buyer and records total balance per listing.
  - `cancelOffer` disburses offer funds per listing and buyer to requester. Checks requester and offer made by the same buyer, pays out offer's total balance, and prevents reentrancy.
  - `closeOffer` disburses offer funds per listing and buyer to marketplace contract. Checks requester has marketplace role (granted to marketplace and auctions contracts only).
- LSP8Auctions (funds)
  - `makeBid` accepts funds per listing. Records total accumulated bid amount. Prevents reentrancy.
  - `cancelBid` disburses total bid balance per listing. Checks for requester and buyer being the same account, and prevents reentrancy.
- UniversalPageName (funds)
  - `reserve` accepts funds and verifies prices and balances restrictions. Mints token and prevents reetrnacy.
  - `release` burns user tokens. Prevents reentrancy and verifies operator of the token.
- PaymentProcessor (funds)
  - `transfer` accepts funds and prevents reentrancy. Checks for zero amount. Pays out full amount to recipient.

## Conclusion

Identified contracts and corresponding functionality are confirmed to be correct and high quality code by running automated tests, security analysis tools, and doing continues manual review and test. All identified major, critical, and informational issues were fixed and/or mitigated.

UniversalPage has performed a best-effort audit of UniversalPage contracts. UniversalPage adheres to industry standards, applying the best practices in code quality, and security. The audit does not guarantee the security or functionality of the smart contract. Not all possible conditions were tested, and a user solely responsible for the proper use and handling of the smart contracts.
