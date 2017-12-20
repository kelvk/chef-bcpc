#!/bin/bash

set -e

source ../shared/shared_functions.sh
export REPO_ROOT="$REPO_ROOT"

load_configs

KNIFE=/opt/opscode/embedded/bin/knife

# Get the management VIP.
MANAGEMENT_VIP=$(vagrant ssh bootstrap -c "$KNIFE environment show $BOOTSTRAP_CHEF_ENV -a override_attributes.bcpc.management.vip | tail -n +2 | awk '{ print \$2 }'")

# Setup SSH tunnel
vagrant ssh-config bootstrap > /tmp/$BOOTSTRAP_CHEF_ENV-bootstrap.ssh.config
ssh -F /tmp/$BOOTSTRAP_CHEF_ENV-bootstrap.ssh.config \
-L 8443:$MANAGEMENT_VIP:443 \
-L 6080:$MANAGEMENT_VIP:6080 bootstrap
