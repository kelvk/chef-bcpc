#
# Cookbook Name:: bcpc
# Recipe:: calico-compute
#
# Copyright 2016, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

apt_repository "calico" do
  uri node['bcpc']['repos']['calico']
  distribution node['lsb']['codename']
  components ["main"]
  key "calico-release.key"
  notifies :run, "execute[apt-get update]", :immediately
end

# installs etcd from calico repo
package "etcd" do
    action :upgrade
end

package "python-etcd" do
    action :upgrade
end

service "etcd" do
    action [:enable]
end

bash "etcd-data-dir" do
  user 'root'
  code <<-EOH
       service etcd stop
       sleep 5
       mount -t tmpfs -o size=512m tmpfs /var/lib/etcd
       egrep '^tmpfs /var/lib/etcd' /etc/fstab || echo 'tmpfs /var/lib/etcd tmpfs nodev,nosuid,noexec,nodiratime,size=512M 0 0' >> /etc/fstab
  EOH
  not_if "mount | egrep '^tmpfs on /var/lib/etcd type tmpfs'"
end

template "/etc/init/etcd.conf" do
    source "etcd.conf.erb"
    owner "root"
    group "root"
    mode 00644
    variables( lazy {
            {
                :members => get_head_nodes
            }
    })
    notifies :start, "service[etcd]", :immediately
end

service "etcd" do
    action [:enable, :start]
end

# Calico uses their own dnsmasq
# apt-get install --only-upgrade dnsmasq-base dnsmasq-utils
package "dnsmasq-base" do
    action :upgrade
end

package "dnsmasq-utils" do
    action :upgrade
end

bash "disable-neutron-dhcp-agent" do
    code "echo manual | tee /etc/init/neutron-dhcp-agent.override"
end

# service neutron-dhcp-agent stop
bash "stop-neutron-dhcp-agent" do
   code "service neutron-dhcp-agent stop"
   ignore_failure true
end

package "calico-dhcp-agent" do
    action :upgrade
end

bash "start-calico-dhcp-agent" do
    code "service calico-dhcp-agent start"
    ignore_failure true
end

package "calico-compute" do
    action :upgrade
end

template "/etc/calico/felix.cfg" do
    source "felix.cfg.erb"
    owner "root"
    group "root"
    mode 00644
    #notifies :start, "service[etcd]", :immediately
end

bash "start-calico-felix" do
    code "service calico-felix restart"
end
