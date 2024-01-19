#!/bin/bash

set -e

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)

help() {
  echo ""
  echo "Usage: $0 -s SCRIPT_NAME -t NETWORK [-b] [-l]"
  echo -e "\t-s --script: Script to run"
  echo -e "\t-t --target: Target network to deploy to"
  echo -e "\t-b --broadcast: Broadcast transactions to a network"
  echo -e "\t-l --libraries: Deploys libraries only"
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
  -t | --target)
    [[ ! "$2" =~ ^- ]] && TARGET=$2
    shift 2
    ;;
  -b | --broadcast)
    BROADCAST=true
    shift
    ;;
  -l | --libraries)
    LIBRARIES=true
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

if [ -z "${TARGET}" ] || ([ -z "${SCRIPT}" ] && [ -z "${LIBRARIES}" ]); then
  help
fi

if [ -n "${SCRIPT}" ] && [ -n "${LIBRARIES}" ]; then
  echo -e "Only can specify script or libraries to deploy"
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
if [ -n "${ADMIN_PRIVATE_KEY}" ]; then
  ARGS+=" --private-key ${ADMIN_PRIVATE_KEY}"
fi

if [ -n "${LIBRARIES}" ]; then

  # known keys
  if [ -z "${ADMIN_PRIVATE_KEY}" ]; then
    # fallback to enter private key
    ARGS+=" --interactive"
  fi

  if [ -z "${LIBRARY_POINTS_ADDRESS}" ]; then
    echo "Deploying Points"
    forge create "${PROJECT_DIR}/src/common/Points.sol:Points" ${ARGS}
  else
    echo "Deployed Points: ${LIBRARY_POINTS_ADDRESS}"
  fi

  if [ -z "${LIBRARY_ROYALTIES_ADDRESS}" ]; then
    echo "Deploying Royalties"
    forge create "${PROJECT_DIR}/src/common/Royalties.sol:Royalties" ${ARGS}
  else
    echo "Deployed Royalties: ${LIBRARY_ROYALTIES_ADDRESS}"
  fi

else

  # fallback to hardware wallet
  if [ -z "${ADMIN_PRIVATE_KEY}" ] && [ -n "${ADMIN_LEDGER_DERIVATION_PATH}" ]; then
    ARGS+=" --ledger --hd-paths ${ADMIN_LEDGER_DERIVATION_PATH}"
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

  forge script "${PROJECT_DIR}/scripts/${SCRIPT}:Deploy" ${ARGS}

fi
