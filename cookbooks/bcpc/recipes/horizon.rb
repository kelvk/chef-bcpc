#
# Cookbook Name:: bcpc
# Recipe:: horizon
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

include_recipe "bcpc::mysql-head"
include_recipe "bcpc::openstack"
include_recipe "bcpc::apache2"
include_recipe "bcpc::cobalt"

ruby_block "initialize-horizon-config" do
    block do
        make_config('mysql-horizon-user', "horizon")
        make_config('mysql-horizon-password', secure_password)
        make_config('horizon-secret-key', secure_password)
    end
end

package "openstack-dashboard" do
    action :upgrade
    notifies :run, "bash[dpkg-reconfigure-openstack-dashboard]", :delayed
end

#  _   _  ____ _  __   __  ____   _  _____ ____ _   _
# | | | |/ ___| | \ \ / / |  _ \ / \|_   _/ ___| | | |
# | | | | |  _| |  \ V /  | |_) / _ \ | || |   | |_| |
# | |_| | |_| | |___| |   |  __/ ___ \| || |___|  _  |
#  \___/ \____|_____|_|   |_| /_/   \_\_| \____|_| |_|

# this patch explicitly sets the Content-Length header when uploading files into
# containers via Horizon
cookbook_file "/tmp/horizon-swift-content-length.patch" do
    source "horizon-swift-content-length.patch"
    owner "root"
    mode 00644
end

bash "patch-for-horizon-swift-content-length" do
    user "root"
    code <<-EOH
       cd /usr/share/openstack-dashboard
       patch -p0 < /tmp/horizon-swift-content-length.patch
       rv=$?
       if [ $rv -ne 0 ]; then
         echo "Error applying patch ($rv) - aborting!"
         exit $rv
       fi
       cp /tmp/horizon-swift-content-length.patch .
    EOH
    not_if "test -f /usr/share/openstack-dashboard/horizon-swift-content-length.patch"
    notifies :restart, "service[apache2]", :delayed
end

package "cobalt-horizon" do
    only_if { not node["bcpc"]["vms_key"].nil? }
    action :upgrade
    options "-o APT::Install-Recommends=0 -o Dpkg::Options::='--force-confnew'"
end

package "openstack-dashboard-ubuntu-theme" do
    action :remove
    notifies :run, "bash[dpkg-reconfigure-openstack-dashboard]", :delayed
end

# This maybe better served by a2disconf
file "/etc/apache2/conf-enabled/openstack-dashboard.conf" do
    action :delete
    notifies :restart, "service[apache2]", :delayed
end
file "/etc/apache2/conf-available/openstack-dashboard.conf" do
    action :delete
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/apache2/sites-available/openstack-dashboard.conf" do
    source "apache-openstack-dashboard.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

bash "apache-enable-openstack-dashboard" do
    user "root"
    code "a2ensite openstack-dashboard"
    not_if "test -r /etc/apache2/sites-enabled/openstack-dashboard"
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/openstack-dashboard/local_settings.py" do
    source "horizon.local_settings.py.erb"
    owner "root"
    group "root"
    mode 00644
    variables(:servers => get_head_nodes)
    notifies :restart, "service[apache2]", :delayed
end

ruby_block "horizon-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['horizon']}\"'|grep \"#{node['bcpc']['dbname']['horizon']}\"" then
            %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['dbname']['horizon']};"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['horizon']}.* TO '#{get_config('mysql-horizon-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-horizon-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['horizon']}.* TO '#{get_config('mysql-horizon-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-horizon-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
            ]
            self.notifies :run, "bash[horizon-database-sync]", :immediately
            self.resolve_notification_references
        end
    end
end

bash "horizon-database-sync" do
    action :nothing
    user "root"
    code "/usr/share/openstack-dashboard/manage.py syncdb --noinput"
    notifies :restart, "service[apache2]", :immediately
end

# needed to regenerate the static assets for the dashboard
bash "dpkg-reconfigure-openstack-dashboard" do
    action :nothing
    user "root"
    code "dpkg-reconfigure openstack-dashboard"
    returns [0, 1]
    notifies :restart, "service[apache2]", :immediately
end