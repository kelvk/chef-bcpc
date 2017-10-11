Converging your cluster with Ansible
===

General notes
---
* **It is recommended that you alias `ansible-playbook -i inventory-file` to something short and convenient, because you will be typing it a lot.**
* You may wish to configure `StrictHostKeyChecking=no` in your `$HOME/.ssh/config` file wile setting up the cluster initially so that the host keys will be automatically accepted. **NOTE THAT DOING SO CONSTITUTES A SECURITY RISK.**

Converging the bootstrap node
---
* Execute `create-operations-user-on-bootstrap.yml`:
```
ansible-playbook -i inventory-file -k -K -e 'ansible_ssh_user=ubuntu' bootstrap_deployment/create-operations-user-on-bootstrap.yml
```
  * This playbook is necessary to get the `operations` user configured on the bootstrap node.
* Execute `converge-bootstrap.yml`:
```
ansible-playbook -i inventory-file bootstrap_deployment/converge-bootstrap.yml
```
  * Remember to save the generated password for the `ubuntu` user somewhere, in case you need emergency access to the bootstrap node (the password can be found in `/root/UBUNTU_PASSWORD`).
  * This playbook calls various tasks in the `bootstrap_deployment` and `software_deployment` directories.
  * This playbook is very complex and does a lot of things that can break, but it is safe to run from the beginning repeatedly if you need to fix things in-flight.
  * As part of package configuration, this will mirror the entire apt repository over to the bootstrap node, which can take several hours.
  * If running this on a virtualized bootstrap node, **ensure that you have available space for another copy of the apt mirror**, as it will all be rsynced into the VM.
* Execute `enroll-all-nodes-in-cobbler.yml`:
```
ansible-playbook -i inventory-file bootstrap_deployment/enroll-all-nodes-in-cobbler.yml
```
  * This playbook executes `bootstrap/ansible_scripts/scripts/enroll_cobbler.py` from the root of the repository on the bootstrap node, which will read `cluster.yaml` or `cluster.yml` and add new nodes as needed; nodes that are already in Cobbler will not be modified.
  * If you have provided an invalid cluster YAML file, this playbook will execute and fail when the cluster YAML file fails validation.
  * If you forgot to include cluster YAML, this playbook will bail out.
  * The cluster YAML is typically injected into the bootstrap node via the `chef-bcpc-prop` repo, which allows inserting and overwriting arbitrary files in the `chef-bcpc` repository.
  * Verify the Cobbler enrollments with `sudo cobbler system list`.
* Reboot cluster nodes and wait for them to be PXE booted and have the OS installed.
  * If you have another DHCP server on the network, you must configure it to use the bootstrap node as `next-server`, or your PXE booting will fail.
  * If you are seeing failures to PXE boot when building locally (especially if you see IP addresses in the **192.168.56.0/24** range), verify that VirtualBox has not snuck a DHCP server in somehow with `VBoxManage list dhcpservers`, and delete any that it have may created.

Join other nodes into the cluster
---
* Create **operations** user on newly booted nodes:
```
ansible-playbook -i inventory-file -k -K -e 'ansible_ssh_user=ubuntu' software_deployment/create-operations-user-on-cluster.yml
```
  * The password for the **ubuntu** user can be obtained from the data bag on the bootstrap node with `knife data bag show configs ENVIRONMENT`.
  * Using the **operations** user for access is recommended.
* Enroll nodes in Chef using `software_deployment/enroll-target-in-chef-server.yml`:
```
ansible-playbook -i inventory-file -e target=xxxx software_deployment/enroll-target-in-chef-server.yml
```
  * `target=xxxx` is an Ansible host pattern, like **headnodes**, **worknodes**, or a specific node name.
* Assign a node's hardware role and cluster role using `software_deployment/assign-roles-to-target.yml`.
  * This playbook will work out the appropriate role based on the hostgroup the node is in, so if a node is in multiple hostgroups Weird Things will happen (i.e., don't put a node in both **[xxxx:headnodes]** and **[xxxx:worknodes]** in the inventory).
  * **NOTE**: do not set the head node role on more than one uncheffed head node at a time, because this will cause failures in Chef resources that use node searches.
  * After adding a new head node, it is advisable to rechef all other head nodes.
* If reinstalling an existing hardware cluster, use `hardware_deployment/erase-data-disks.yml` with the **target** option to destroy existing Ceph/LVM partition tables and structures to avoid problems when recheffing.
  * This playbook is obviously extremely dangerous and will bail if it detects Ceph or nova-compute processes on any target, **USE AT YOUR OWN RISK**.
* Chef the node using `software_deployment/chef-target.yml`:
```
ansible-playbook -i inventory-file -e target=xxxx software_deployment/chef-target.yml
```
* After all nodes have been cheffed, rechef the entire cluster to ensure all config files are properly up to date:
```
ansible-playbook -i inventory-file software_deployment/chef-cluster.yml
```
