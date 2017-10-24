#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

source "$REPO_ROOT/bootstrap/shared/shared_functions.sh"
load_configs
REQUIRED_VARS=( BOOTSTRAP_CHEF_ENV BCPC_HYPERVISOR_DOMAIN CLUSTER )
check_for_envvars "${REQUIRED_VARS[@]}"

CLUSTER_CONFIG="$REPO_ROOT/bootstrap/config/$CLUSTER.json"

# Run chef-client on nodes, twice
do_on_node bootstrap "sudo chef-client"
vms="`cat $CLUSTER_CONFIG | jq -r '.nodes | to_entries[] | select(.value.chef_role != \"BCPC-Bootstrap\") | .key' | awk -F'-' '{print $NF}'`"
for i in `seq 1 2`; do
  for vm in $vms; do
    do_on_node $vm "sudo chef-client"
  done
done
