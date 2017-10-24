#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

. "$REPO_ROOT/bootstrap/shared/shared_functions.sh"

REQUIRED_VARS=( BOOTSTRAP_CHEF_DO_CONVERGE BOOTSTRAP_CHEF_ENV BCPC_HYPERVISOR_DOMAIN FILECACHE_MOUNT_POINT REPO_MOUNT_POINT REPO_ROOT CLUSTER )
check_for_envvars "${REQUIRED_VARS[@]}"

CLUSTER_CONFIG="$REPO_ROOT/bootstrap/config/$CLUSTER.json"
# This script does a lot of stuff:
# - installs Chef Server on the bootstrap node
# - installs Chef client on all nodes

# It would be more efficient as something executed in one shot on each node, but
# doing it this way makes it easy to orchestrate operations between nodes. In some cases,
# commands can be &&'d together to avoid SSHing repeatedly to a node (SSH setup/teardown
# can add a fair amount of time to this script).

cd "$REPO_ROOT/bootstrap/vagrant_scripts"

# use Chef Server embedded knife instead of the one in /usr/bin
KNIFE=/opt/opscode/embedded/bin/knife

# install and configure Chef Server 12 and Chef 12 client on the bootstrap node
# move nginx insecure to 4000/TCP is so that Cobbler can run on the regular 80/TCP
if [[ -n "$CHEF_SERVER_DEB" ]]; then
    debpath="$FILECACHE_MOUNT_POINT/$CHEF_SERVER_DEB"
    CHEF_SERVER_INSTALL_CMD="sudo dpkg -i $debpath"
else
    CHEF_SERVER_INSTALL_CMD="sudo dpkg -i \$(find $FILECACHE_MOUNT_POINT/ -name chef-server\*deb -not -name \*downloaded | tail -1)"
fi
if [[ -n "$CHEF_CLIENT_DEB" ]]; then
    debpath="$FILECACHE_MOUNT_POINT/$CHEF_CLIENT_DEB"
    CHEF_CLIENT_INSTALL_CMD="sudo dpkg -i $debpath"
else
    CHEF_CLIENT_INSTALL_CMD="sudo dpkg -i \$(find $FILECACHE_MOUNT_POINT/ -name chef_\*deb -not -name \*downloaded | tail -1)"
fi
unset debpath

echo "Installing Chef server..."

do_on_node bootstrap "$CHEF_SERVER_INSTALL_CMD \
  && sudo sh -c \"echo nginx[\'non_ssl_port\'] = 4000 > /etc/opscode/chef-server.rb\" \
  && sudo chef-server-ctl reconfigure \
  && sudo chef-server-ctl user-create admin admin admin admin@localhost.com welcome --filename /etc/opscode/admin.pem \
  && sudo chef-server-ctl org-create bcpc BCPC --association admin --filename /etc/opscode/bcpc-validator.pem \
  && sudo chmod 0644 /etc/opscode/admin.pem /etc/opscode/bcpc-validator.pem \
  && $CHEF_CLIENT_INSTALL_CMD"

# configure knife on the bootstrap node and perform a knife bootstrap to create the bootstrap node in Chef
echo "Configuring Knife on bootstrap node..."

do_on_node bootstrap "mkdir -p \$HOME/.chef && echo -e \"chef_server_url 'https://bcpc-dev-bootstrap.$BCPC_HYPERVISOR_DOMAIN/organizations/bcpc'\\\nvalidation_client_name 'bcpc-validator'\\\nvalidation_key '/etc/opscode/bcpc-validator.pem'\\\nnode_name 'admin'\\\nclient_key '/etc/opscode/admin.pem'\\\nknife['editor'] = 'vim'\\\ncookbook_path [ \\\"#{ENV['HOME']}/chef-bcpc/cookbooks\\\" ]\" > \$HOME/.chef/knife.rb \
  && $KNIFE ssl fetch"

# install the knife-acl plugin into embedded knife, rsync the Chef repository into the non-root user
# (vagrant)'s home directory, and add the dependency cookbooks from the file cache
echo "Installing knife-acl plugin..."

do_on_node bootstrap "sudo /opt/opscode/embedded/bin/gem install -l $FILECACHE_MOUNT_POINT/knife-acl-1.0.2.gem \
  && rsync -a $REPO_MOUNT_POINT/* \$HOME/chef-bcpc \
  && cp $FILECACHE_MOUNT_POINT/cookbooks/*.tar.gz \$HOME/chef-bcpc/cookbooks \
  && cd \$HOME/chef-bcpc/cookbooks && ls -1 *.tar.gz | xargs -I% tar xvzf %"

# build binaries before uploading the bcpc cookbook
# (this step will change later but using the existing build_bins script for now)
echo "Building binaries..."

do_on_node bootstrap "sudo apt-get update \
  && sudo apt-get -y autoremove \
  && cd \$HOME/chef-bcpc \
  && sudo bash -c 'export FILECACHE_MOUNT_POINT=$FILECACHE_MOUNT_POINT \
  && source \$HOME/proxy_config.sh && bootstrap/shared/shared_build_bins.sh'"

# upload all cookbooks, roles and our chosen environment to the Chef server
# (cookbook upload uses the cookbook_path set when configuring knife on the bootstrap node)
do_on_node bootstrap "$KNIFE cookbook upload -a \
  && cd \$HOME/chef-bcpc/roles && $KNIFE role from file *.json \
  && cd \$HOME/chef-bcpc/environments && $KNIFE environment from file $BOOTSTRAP_CHEF_ENV.json"

# install and bootstrap Chef on cluster nodes
echo "Installing Chef client on cluster nodes..."

vms="`cat $CLUSTER_CONFIG | egrep -o bcpc-dev-[a-z0-9]+ | sed 's/bcpc-dev-//g'`"
for vm in $vms; do
  # Remove configuration management software that might be preinstalled in the box
  do_on_node "$vm" "sudo dpkg -P puppet chef"
  # Try to install a specific version, or just the latest
  if [[ -z "$CHEF_CLIENT_DEB" ]]; then
    echo "Installing latest chef-client found in $vm:$FILECACHE_MOUNT_POINT"
  fi
  do_on_node "$vm" "$CHEF_CLIENT_INSTALL_CMD"
done

# Configure Chef clients/nodes
do_on_node bootstrap "cd $REPO_MOUNT_POINT \
  && sudo bash -c 'export REPO_MOUNT_POINT=$REPO_MOUNT_POINT \
  && bootstrap/shared/shared_configure_chef_clients.sh'"

# Run chef-client on nodes if we want auto-convergence
if [[ $BOOTSTRAP_CHEF_DO_CONVERGE -eq 1 ]]; then
  "$REPO_ROOT"/bootstrap/shared/shared_converge_chef.sh
fi
