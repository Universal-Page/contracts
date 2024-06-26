#!/bin/bash

set -e

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)

help() {
  echo ""
  echo "Usage: $0 -t NETWORK"
  echo -e "\t-t --target: Target network to deploy to"
  echo -e "\t-h --help: Prints this message"
  exit 1
}

while [ -n "$1" ]; do
  case "$1" in
  -h | --help)
    help
    ;;
  -t | --target)
    [[ ! "$2" =~ ^- ]] && TARGET=$2
    shift 2
    ;;
  --)
    # remaining options are captured as "$*"
    shift
    break
    ;;
  *)
    echo -e "Unknown option: $1"
    help
    ;;
  esac
done

if [ -z "${TARGET}" ]; then
  help
fi

case "${TARGET}" in
local | testnet | mainnet | base.sepolia) ;;
*)
  echo -e "Unknown target: ${TARGET}"
  help
  ;;
esac

set -a
source "${PROJECT_DIR}/.env"
source "${PROJECT_DIR}/.env.${TARGET}"
set +a

SRC_DIR=${PROJECT_DIR}/src

verify() {
  local name=$1
  local address=$2

  echo "Verifying ${name} at ${address}"

  forge verify-contract \
    --optimizer-runs 1000 \
    --chain-id ${CHAIN_ID} \
    --verifier blockscout \
    --verifier-url "${BLOCKSCOUT_URL}/api" \
    --watch \
    ${address} ${name}
}

verifyProxy() {
  local name=$1
  local address=$2

  echo "Verifying proxy ${name} at ${address}"

  implementationValue=$(
    cast storage \
      --chain ${CHAIN_ID} \
      --rpc-url ${RPC_URL} \
      ${address} 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
  )
  implementationAddress="0x${implementationValue:26:40}"

  echo "Implementation address: ${implementationAddress}"

  verify TransparentUpgradeableProxy ${address}
  verify ${name} ${implementationAddress}
}

forge build

verify Points ${LIBRARY_POINTS_ADDRESS}
verify Royalties ${LIBRARY_ROYALTIES_ADDRESS}

if [ -n "${CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS}" ]; then
  verify CollectorIdentifiableDigitalAsset ${CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS}
fi

if [ -n "${CONTRACT_GENESIS_DIGITAL_ASSET_ADDRESS}" ]; then
  verify GenesisDigitalAsset ${CONTRACT_GENESIS_DIGITAL_ASSET_ADDRESS}
fi

verifyProxy Participant ${CONTRACT_PARTICIPANT_ADDRESS}

verifyProxy LSP7Listings ${CONTRACT_LSP7_LISTINGS_ADDRESS}
verifyProxy LSP7Offers ${CONTRACT_LSP7_OFFERS_ADDRESS}
verifyProxy LSP7Orders ${CONTRACT_LSP7_ORDERS_ADDRESS}
verifyProxy LSP7Marketplace ${CONTRACT_LSP7_MARKETPLACE_ADDRESS}

verifyProxy LSP8Listings ${CONTRACT_LSP8_LISTINGS_ADDRESS}
verifyProxy LSP8Offers ${CONTRACT_LSP8_OFFERS_ADDRESS}
verifyProxy LSP8Auctions ${CONTRACT_LSP8_AUCTIONS_ADDRESS}
verifyProxy LSP8Marketplace ${CONTRACT_LSP8_MARKETPLACE_ADDRESS}

verifyProxy PageName ${CONTRACT_PAGE_NAME_ADDRESS}

if [ -n "${CONTRACT_POOL_VAULT}" ]; then
  verifyProxy Vault ${CONTRACT_POOL_VAULT}
fi

if [ -n "${CONTRACT_ELECTIONS}" ]; then
  verifyProxy Elections ${CONTRACT_ELECTIONS}
fi

if [ -n "${CONTRACT_PROFILES_ORACLE}" ]; then
  verifyProxy ProfilesOracle ${CONTRACT_PROFILES_ORACLE}
fi

verify ProfilesReverseLookup ${CONTRACT_PROFILES_REVERSE_LOOKUP}
