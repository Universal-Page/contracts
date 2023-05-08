#!/bin/bash

set -e

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)

source "${PROJECT_DIR}/.env"
source "${PROJECT_DIR}/.env.local"

anvil \
  --mnemonic "${MNEMONIC}" \
  --derivation-path "m/44'/60'/0'/0/"
