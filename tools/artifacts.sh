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
ABI_DIR=${PROJECT_DIR}/artifacts/abi
BYTECODE_DIR=${PROJECT_DIR}/artifacts/bytecode/${CHAIN_ID}

exportAbi() {
  path=$(dirname $1)
  name=$(basename $1)

  echo "Exporting abi ${name}"
  mkdir -p "${ABI_DIR}/${path}"
  forge inspect "${SRC_DIR}/${path}/${name}.sol:${name}" abi \
    >"${ABI_DIR}/${path}/${name}.json"
}

exportBytecode() {
  path=$(dirname $1)
  name=$(basename $1)

  echo "Exporting bytecode ${name}"
  mkdir -p "${BYTECODE_DIR}/${path}"
  forge inspect "${SRC_DIR}/${path}/${name}.sol:${name}" bytecode \
    --force \
    --optimize \
    --optimizer-runs 1000 \
    --libraries src/common/Points.sol:Points:${LIBRARY_POINTS_ADDRESS} \
    --libraries src/common/Royalties.sol:Royalties:${LIBRARY_ROYALTIES_ADDRESS} \
    >"${BYTECODE_DIR}/${path}/${name}.bin"
}

exportAbi "assets/lsp7/GenesisDigitalAsset"

exportAbi "assets/lsp7/DigitalAssetDrop"
exportBytecode "assets/lsp7/DigitalAssetDrop"

exportAbi "assets/lsp7/MintableDigitalAsset"
exportBytecode "assets/lsp7/MintableDigitalAsset"

exportAbi "assets/lsp8/MintableIdentifiableDigitalAsset"
exportBytecode "assets/lsp8/MintableIdentifiableDigitalAsset"

exportAbi "assets/lsp8/CollectorIdentifiableDigitalAsset"

exportAbi "drops/LSP7DropsDigitalAsset"
exportBytecode "drops/LSP7DropsDigitalAsset"
exportAbi "drops/LSP7DropsLightAsset"
exportBytecode "drops/LSP7DropsLightAsset"

exportAbi "drops/LSP8DropsDigitalAsset"
exportBytecode "drops/LSP8DropsDigitalAsset"
exportAbi "drops/LSP8DropsLightAsset"
exportBytecode "drops/LSP8DropsLightAsset"

exportAbi "marketplace/Participant"

exportAbi "marketplace/lsp7/LSP7Listings"
exportAbi "marketplace/lsp7/LSP7Offers"
exportAbi "marketplace/lsp7/LSP7Orders"
exportAbi "marketplace/lsp7/LSP7Marketplace"

exportAbi "marketplace/lsp8/LSP8Listings"
exportAbi "marketplace/lsp8/LSP8Offers"
exportAbi "marketplace/lsp8/LSP8Auctions"
exportAbi "marketplace/lsp8/LSP8Marketplace"

exportAbi "page/PageName"

exportAbi "pool/Vault"
exportAbi "pool/IDepositContract"

exportAbi "profiles/ProfilesOracle"

exportAbi "Elections"
