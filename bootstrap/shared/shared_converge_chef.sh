#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

source "$REPO_ROOT/bootstrap/shared/shared_functions.sh"
load_configs
REQUIRED_VARS=( BOOTSTRAP_CHEF_ENV BCPC_HYPERVISOR_DOMAIN CLUSTER )
check_for_envvars "${REQUIRED_VARS[@]}"

CLUSTER_CONFIG="$REPO_ROOT/bootstrap/config/$CLUSTER.json"

# Built list of VMs we want to prioritize running Chef on
priority_roles='BCPC-Bootstrap BCPC-Headnode BCPC-CephMonitorNode'
priority_vms=()
for role in ${priority_roles[@]}; do
  vms="`cat $CLUSTER_CONFIG | jq -r '.nodes | to_entries[] | select(.value.chef_role == "'$role'") | .key' | awk -F'-' '{print $NF}'`"
  priority_vms+=($vms)
  normal_vm_filter+=".value.chef_role != \"$role\" and"
done
normal_vm_filter="`echo $normal_vm_filter | sed 's/ and$//g'`"

# Obtain VMs that do not meet the priority requirement
vms="`cat $CLUSTER_CONFIG | jq -r '.nodes | to_entries[] | select('"$normal_vm_filter"') | .key' | awk -F'-' '{print $NF}'`"

# Run chef-client on nodes, twice
for i in `seq 1 2`; do
  for vm in ${priority_vms[*]} $vms; do
    do_on_node $vm "sudo chef-client"
  done
done
