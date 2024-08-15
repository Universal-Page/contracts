#!/bin/bash

set -e

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)

help() {
  echo ""
  echo "Usage: $0 -s SCRIPT_NAME -t NETWORK [-b] [-p] [-n SCRIPT_NAME]"
  echo -e "\t-s --script: Script to run"
  echo -e "\t-t --target: Target network"
  echo -e "\t-b --broadcast: Broadcast transactions to a network"
  echo -e "\t-p --profile: Use Universal Page profile to transact on behalf"
  echo -e "\t-n --name: Name of script contract or 'Configure' if not specified"
  echo -e "\t-h --help: Prints this message"
  exit 1
}

while [ -n "$1" ]; do
  case "$1" in
  -h | --help)
    help
    ;;
  -s | --script)
    [[ ! "$2" =~ ^- ]] && SCRIPT=$2
    shift 2
    ;;
  -n | --name)
    [[ ! "$2" =~ ^- ]] && SCRIPT_NAME=$2
    shift 2
    ;;
  -t | --target)
    [[ ! "$2" =~ ^- ]] && TARGET=$2
    shift 2
    ;;
  -b | --broadcast)
    BROADCAST=true
    shift
    ;;
  -p | --profile)
    PROFILE=true
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

if [ -z "${TARGET}" ] || [ -z "${SCRIPT}" ]; then
  help
fi

if [ -z "${SCRIPT_NAME}" ]; then
  SCRIPT_NAME="Configure"
fi

case "${TARGET}" in
local | testnet | mainnet | base.sepolia | base) ;;
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

# use profile's controller or fallback to hardware wallet
if [ "${PROFILE}" = true ]; then
  ARGS+=" --ledger --hd-paths ${PROFILE_CONTROLLER_LEDGER_DERIVATION_PATH}"
elif [ -n "${OWNER_PRIVATE_KEY}" ]; then
  ARGS+=" --private-keys ${OWNER_PRIVATE_KEY}"
elif [ -n "${OWNER_LEDGER_DERIVATION_PATH}" ]; then
  ARGS+=" --ledger --hd-paths ${OWNER_LEDGER_DERIVATION_PATH}"
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

forge script "${PROJECT_DIR}/scripts/${SCRIPT}:${SCRIPT_NAME}" ${ARGS}
