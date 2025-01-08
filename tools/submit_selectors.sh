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
local | testnet | mainnet) ;;
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

submit() {
  path=$(dirname $1)
  name=$(basename $1)

  # forge inspect ${name} methodIdentifiers

  abi=$(forge inspect "${SRC_DIR}/${path}/${name}.sol:${name}" abi)
  content="{ \"contract_abi\": ${abi} }"

  echo "Submitting selectors of ${name} to openchain.xyz"
  forge selectors upload ${name}

  # echo "Submitting selectors of ${name} to 4byte.directory"
  # curl \
  #   --header "Content-Type: application/json" \
  #   --request POST \
  #   --data "${content}" \
  #   "https://www.4byte.directory/api/v1/import-solidity/"
}

submit "assets/lsp7/GenesisDigitalAsset"

submit "assets/lsp7/DigitalAssetDrop"

submit "assets/lsp7/MintableDigitalAsset"

submit "assets/lsp8/MintableIdentifiableDigitalAsset"

submit "assets/lsp8/CollectorIdentifiableDigitalAsset"

submit "drops/LSP7DropsDigitalAsset"

submit "drops/LSP8DropsDigitalAsset"

submit "marketplace/Participant"

submit "marketplace/lsp7/LSP7Listings"
submit "marketplace/lsp7/LSP7Offers"
submit "marketplace/lsp7/LSP7Orders"
submit "marketplace/lsp7/LSP7Marketplace"

submit "marketplace/lsp8/LSP8Listings"
submit "marketplace/lsp8/LSP8Offers"
submit "marketplace/lsp8/LSP8Orders"
submit "marketplace/lsp8/LSP8Auctions"
submit "marketplace/lsp8/LSP8Marketplace"

submit "page/PageName"

submit "pool/Vault"
