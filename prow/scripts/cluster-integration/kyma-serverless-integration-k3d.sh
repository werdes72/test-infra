#!/usr/bin/env bash

set -o errexit
set -o pipefail # Fail a pipe if any sub-command fails.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prow/scripts/cluster-integration/kyma-serverless-run-test.sh
source "${SCRIPT_DIR}/kyma-serverless-run-test.sh"
# shellcheck source=prow/scripts/lib/serverless-shared-k3s.sh
source "${SCRIPT_DIR}/../lib/serverless-shared-k3s.sh"

date

export DOMAIN=${KYMA_DOMAIN:-local.kyma.dev}
if [[ -z $REGISTRY_VALUES ]]; then
  export REGISTRY_VALUES="dockerRegistry.enableInternal=false,dockerRegistry.serverAddress=registry.localhost:5000,dockerRegistry.registryAddress=registry.localhost:5000"
fi

export KYMA_SOURCES_DIR="./kyma"
export INTEGRATION_SUITE=${1:-serverless-integration}

echo "--> Installing kyma-cli"
install::kyma_cli

echo "--> Provisioning k3d cluster for Kyma"
kyma provision k3d --ci

echo "--> Deploying Serverless"
# The python38 function requires 40M+ of memory to work. Mostly used by kubeless. I need to overrride the defaultPreset to M to avoid OOMkill.

echo "--> Deploying Serverless from $KYMA_SOURCES_DIR"
kyma deploy --ci \
  --component cluster-essentials \
  --component serverless \
  --value "$REGISTRY_VALUES" \
  --value global.ingress.domainName="$DOMAIN" \
  --value "serverless.webhook.values.function.resources.defaultPreset=M" \
  --value "serverless.webhook.values.featureFlags.java17AlphaEnabled=true" \
  -s local -w $KYMA_SOURCES_DIR

echo "##############################################################################"
# shellcheck disable=SC2004
echo "# Serverless installed in $(($SECONDS / 60)) min $(($SECONDS % 60)) sec"
echo "##############################################################################"

# TODO: I can consider to remove this and use loop for ready webhook and operator
# I know it's bad practice and kinda smelly to do this, but we have two nasty dataraces that might happen, and simple sleep solves them both:
# webhook might not be ready in time (but somehow it still accepts the function, we have an issue for that)
# runtime configmaps might now have been copied to that namespace, but it should be handled by https://github.com/kyma-project/kyma/pull/10026
########
sleep 60
########

set +o errexit
run_tests "${INTEGRATION_SUITE}" "${KYMA_SOURCES_DIR}"
TEST_STATUS=$?
set -o errexit

collect_results
echo "Exit code ${TEST_STATUS}"

exit ${TEST_STATUS}
