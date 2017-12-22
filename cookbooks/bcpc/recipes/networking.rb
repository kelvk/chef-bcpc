#
# Cookbook Name:: bcpc
# Recipe:: networking
#
# Copyright 2013, Bloomberg Finance L.P.
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

include_recipe "bcpc::default"
include_recipe "bcpc::certs"

template "/etc/hosts" do
    source "hosts.erb"
    mode 00644
    variables(
      lazy {
        {
          :servers => get_all_nodes,
          :bootstrap_node => get_bootstrap_node
        }
      }
    )
end

template "/etc/ssh/sshd_config" do
    source "sshd_config.erb"
    mode 00644
    notifies :restart, "service[ssh]", :immediately
end

service "ssh" do
    action [:enable, :start]
end

service "cron" do
    action [:enable, :start]
end

# Core networking package
package "vlan"

# Enable LLDP - see https://github.com/bloomberg/chef-bcpc/pull/120
package "lldpd"

bash "enable-mellanox" do
    user "root"
    code <<-EOH
        if [ -z "`lsmod | grep mlx4_en`" ]; then
            modprobe mlx4_en
        fi
        if [ -z "`grep mlx4_en /etc/modules`" ]; then
            echo "mlx4_en" >> /etc/modules
        fi
    EOH
    only_if "lspci | grep Mellanox"
end

bash "enable-8021q" do
    user "root"
    code <<-EOH
        modprobe 8021q
        sed --in-place '/^8021q/d' /etc/modules
        echo '8021q' >> /etc/modules
    EOH
    not_if "grep -e '^8021q' /etc/modules"
end

# needed for kernel 3.18+
bash "enable-br_netfilter" do
    user "root"
    code <<-EOH
        modprobe br_netfilter
        sed --in-place '/^br_netfilter/d' /etc/modules
        echo 'br_netfilter' >> /etc/modules
    EOH
    only_if do
      mod_present_cmd = Mixlib::ShellOut.new('modinfo br_netfilter').run_command
      grep_cmd = Mixlib::ShellOut.new("grep -e '^br_netfilter' /etc/modules").run_command
      !mod_present_cmd.error? && grep_cmd.error? && !node['bcpc']['monitoring']['provider']
    end
end

directory "/etc/network/interfaces.d" do
    owner "root"
    group "root"
    mode 00755
    action :create
end

bash "setup-interfaces-source" do
    user "root"
    code <<-EOH
        echo "source /etc/network/interfaces.d/iface-*" >> /etc/network/interfaces
    EOH
    not_if "grep '^source /etc/network/interfaces.d/iface-' /etc/network/interfaces"
end

[['management', 100], ['storage', 300]].each do |net, metric|
    template "/etc/network/interfaces.d/iface-#{node['bcpc'][net]['interface']}" do
        source "network.iface.erb"
        owner "root"
        group "root"
        mode 00644
        variables(
            :interface => node['bcpc'][net]['interface'],
            :ip => node['bcpc'][net]['ip'],
            :netmask => node['bcpc'][net]['netmask'],
            :gateway => node['bcpc'][net]['gateway'],
            :mtu => node['bcpc'][net]['mtu'],
            :metric => metric
        )
    end

end

%w{ storage floating }.each do |net|
  if not node['bcpc'][net]['interface-parent'].nil?
    # safeguard to prevent cutting off management network access if
    # the management interface is on the native VLAN and floating/storage
    # is on a tagged VLAN on the same physical interface
    if node['bcpc'][net]['interface-parent'] == node['bcpc']['management']['interface']
      raise "#{net} interface parent is in use as the management interface, refusing to configure interface parent. Please unset interface parent on the #{net} interface in the hardware role."
    end

    template "/etc/network/interfaces.d/iface-#{node['bcpc'][net]['interface-parent']}" do
      source "network.iface-parent.erb"
      owner "root"
      group "root"
      mode 00644
      variables(
        :interface => node['bcpc'][net]['interface-parent'],
        :mtu => node['bcpc'][net]['mtu'],
      )
    end
  end
end

# set up the DNS resolvers
# we want the VIP which will be running powerdns to be first on the list
# but the first entry in our master list is also the only one in pdns,
# so make that the last entry to minimize double failures when upstream dies.
resolvers=node['bcpc']['dns_servers'].dup
resolvers.push resolvers.shift
resolvers.unshift node['bcpc']['management']['vip']

template "/etc/network/interfaces.d/iface-#{node['bcpc']['floating']['interface']}" do
    source "network.iface.erb"
    owner "root"
    group "root"
    mode 00644
    variables(
        :interface => node['bcpc']['floating']['interface'],
        :ip => node['bcpc']['floating']['ip'],
        :netmask => node['bcpc']['floating']['netmask'],
        :gateway => node['bcpc']['floating']['gateway'],
        :dns => resolvers,
        :mtu => node['bcpc']['floating']['mtu'],
        :metric => 200
    )
end

dhcp_resolvconf_hook="/etc/dhcp/dhclient-enter-hooks.d/resolvconf"
bash "disable-dhclient-resolvconf-enter-hook" do
    user "root"
    code <<-EOH
        gzip #{dhcp_resolvconf_hook}
        resolvconf --enable-updates
        resolvconf -d #{node['bcpc']['management']['interface']}.dhclient
    EOH
    only_if { ::File.exists?(dhcp_resolvconf_hook) }
end

bash "interface-mgmt-make-static-if-dhcp" do
    user "root"
    code <<-EOH
        sed --in-place '/\\(.*#{node['bcpc']['management']['interface']}.*\\)/d' /etc/network/interfaces
        resolvconf -d #{node['bcpc']['management']['interface']}.dhclient
    EOH
    only_if "cat /etc/network/interfaces | grep #{node['bcpc']['management']['interface']} | grep dhcp"
end

%w{ management storage floating }.each do |iface|

  if not node['bcpc'][iface]['interface-parent'].nil?
    bash "#{iface} up" do
      user "root"
      code <<-EOH
            ifup #{node['bcpc'][iface]['interface-parent']}
        EOH
      not_if "ip link show up | grep #{node['bcpc'][iface]['interface-parent']} | grep -v #{node['bcpc'][iface]['interface']}"
    end
    if node['bcpc'][iface]['mtu']
        execute "set-#{iface}-mtu" do
            command "ifconfig #{node['bcpc'][iface]['interface-parent']} mtu #{node['bcpc'][iface]['mtu']} up"
            not_if  "ifconfig #{node['bcpc'][iface]['interface-parent']} | grep MTU:#{node['bcpc'][iface]['mtu']}"
        end
    end
  end

    bash "#{iface} up" do
        user "root"
        code <<-EOH
            ifup #{node['bcpc'][iface]['interface']}
        EOH
        not_if "ip link show up | grep #{node['bcpc'][iface]['interface']}"
    end

    if node['bcpc'][iface]['mtu']
        execute "set-#{iface}-mtu" do
            command "ifconfig #{node['bcpc'][iface]['interface']} mtu #{node['bcpc'][iface]['mtu']} up"
            not_if  "ifconfig #{node['bcpc'][iface]['interface']} | grep MTU:#{node['bcpc'][iface]['mtu']}"
        end
    end

end

bash "routing-management" do
    user "root"
    code "echo '1 mgmt' >> /etc/iproute2/rt_tables"
    not_if "grep -e '^1 mgmt' /etc/iproute2/rt_tables"
end

bash "routing-storage" do
    user "root"
    code "echo '2 storage' >> /etc/iproute2/rt_tables"
    not_if "grep -e '^2 storage' /etc/iproute2/rt_tables"
end

if node['bcpc']['monitoring']['provider']
    function = 'ipset-monitoring'
    # ipset is used to maintain largish block(s) of IP addresses to be referred to
    # by iptables
    package "ipset"

    # Insert numbering so it runs before /etc/network/if-up.d/bcpc-firewall
    template "/etc/network/if-up.d/001bcpc-#{function}" do
        mode 00775
        source "bcpc-#{function}.erb"
        notifies :run, "execute[run-#{function}-script]", :delayed
    end

    template "/etc/#{function}-clients.conf" do
        mode 00600
        source "#{function}-clients.conf.erb"
        variables(
            :clients => node['bcpc']['monitoring']['external_clients'].sort
        )
        notifies :run, "execute[run-#{function}-script]", :immediately
    end

    execute "run-#{function}-script" do
        action :nothing
        command "/etc/network/if-up.d/001bcpc-#{function}"
    end

end

network_functions = %w(firewall)
network_functions += ['routing'] unless node['bcpc']['enabled']['neutron']

network_functions.each do |function|
    template "/etc/network/if-up.d/bcpc-#{function}" do
        mode 00775
        source "bcpc-#{function}.erb"
        notifies :run, "execute[run-#{function}-script-once]", :immediately
    end

    execute "run-#{function}-script-once" do
        action :nothing
        command "/etc/network/if-up.d/bcpc-#{function}"
    end
end


bash "disable-noninteractive-pam-logging" do
    user "root"
    code "sed --in-place 's/^\\(session\\s*required\\s*pam_unix.so\\)/#\\1/' /etc/pam.d/common-session-noninteractive"
    only_if "grep -e '^session\\s*required\\s*pam_unix.so' /etc/pam.d/common-session-noninteractive"
end
