#!/bin/bash

set -e

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)

help() {
  echo ""
  echo "Usage: $0 -t NETWORK [-b]"
  echo -e "\t-t --target: Target network"
  echo -e "\t-b --broadcast: Broadcast transactions to a network"
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
  -b | --broadcast)
    BROADCAST=true
    shift
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

# script arguments
ARGS="--rpc-url ${RPC_URL}"

# known keys
if [ -n "${PROFILE_CONTROLLER_PRIVATE_KEY}" ]; then
  ARGS+=" --private-keys ${PROFILE_CONTROLLER_PRIVATE_KEY}"
fi
if [ -n "${OWNER_PRIVATE_KEY}" ]; then
  ARGS+=" --private-keys ${OWNER_PRIVATE_KEY}"
fi

# broadcast
if [ "${BROADCAST}" = true ]; then
  ARGS+=" --broadcast"
fi

# libraries
if [ -n "${LIBRARY_POINTS_ADDRESS}" ]; then
  ARGS+=" --libraries src/common/Points.sol:Points:${LIBRARY_POINTS_ADDRESS}"
fi
if [ -n "${LIBRARY_ROYALTIES_ADDRESS}" ]; then
  ARGS+=" --libraries src/common/Royalties.sol:Royalties:${LIBRARY_ROYALTIES_ADDRESS}"
fi

forge script "${PROJECT_DIR}/scripts/Playground.s.sol:Playground" ${ARGS}
