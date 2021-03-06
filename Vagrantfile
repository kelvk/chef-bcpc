# -*- mode: ruby -*-
# vi: set ft=ruby :

# This is a Vagrant to automatically provision a bootstrap node with a
# Chef server.
# See http://www.vagrantup.com/ for info on Vagrant.

$local_environment = "Test-Laptop"
$local_mirror = ENV["BOOTSTRAP_APT_MIRROR"]

if $local_mirror.nil? or $local_mirror.empty?
  $repos_script = <<EOH
EOH
else
  $repos_script = <<EOH
#!/bin/bash
hash -r
install -d -m0755 -g adm /var/log/vagrant
exec &>>/var/log/vagrant/provision.log
date --rfc-3339=s
set -x
sed -i s/archive.ubuntu.com/#{$local_mirror}/g /etc/apt/sources.list
sed -i s/security.ubuntu.com/#{$local_mirror}/g /etc/apt/sources.list
sed -i s/^deb-src/\#deb-src/g /etc/apt/sources.list
touch /etc/apt/apt.conf
echo 'Acquire::http::Proxy::#{$local_mirror.split(':')[0]} "DIRECT";' >> /etc/apt/apt.conf
apt-get update
EOH
end

Vagrant.configure("2") do |config|

  config.vm.define :bootstrap do |bootstrap|
    bootstrap.vm.hostname = "bcpc-bootstrap"

    bootstrap.vm.network :private_network, ip: "10.0.100.3", netmask: "255.255.255.0", adapter_ip: "10.0.100.2"
    bootstrap.vm.network :private_network, ip: "172.16.100.3", netmask: "255.255.255.0", adapter_ip: "172.16.100.2"
    bootstrap.vm.network :private_network, ip: "192.168.100.3", netmask: "255.255.255.0", adapter_ip: "192.168.100.2"

    bootstrap.vm.synced_folder "../", "/chef-bcpc-host"

    # fix no-tty error
    bootstrap.vm.provision "fix-no-tty", type: "shell" do |s|
      s.privileged = false
      s.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
    end

    # set up repositories
    bootstrap.vm.provision "configure-repositories", type: "shell" do |s|
      s.inline = $repos_script
    end

    # since we are creating the server and the validation keys on this new
    # machine itself, we can't use Vagrant's built-in chef provisioning.
    # We actually prefer to do this in vbox_create.sh as we do some fixups
    # and register our VMs in cobbler after we're done.
    #bootstrap.vm.provision :shell, :inline => "/chef-bcpc-host/bootstrap_chef.sh --vagrant-local 10.0.100.3 #{$local_environment}"
  end

  #config.vm.define :mirror do |mirror|
  #  mirror.vm.hostname = "bcpc-mirror-vagrant"
#
#    mirror.vm.network :private_network, ip: "10.0.100.4", netmask: "255.255.255.0", adapter_ip: "10.0.100.2"
#    mirror.vm.network :private_network, ip: "172.16.100.4", netmask: "255.255.255.0", adapter_ip: "172.16.100.2"
#    mirror.vm.network :private_network, ip: "192.168.100.4", netmask: "255.255.255.0", adapter_ip: "192.168.100.2"
#
#  end

  config.vm.box = "trusty64"
  #config.vm.box_url = "http://cloud-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-vagrant-disk1.box"
  config.vm.box_url = "trusty-server-cloudimg-amd64-vagrant-disk1.box"

  memory = ( ENV["BOOTSTRAP_VM_MEM"] or "2048" )
  cpus = ( ENV["BOOTSTRAP_VM_CPUS"] or "1" )
  vram = ( ENV["BOOTSTRAP_VM_VRAM"] or "16" )

  config.vm.provider :virtualbox do |vb|
     vb.name = "bcpc-bootstrap"
     vb.customize ["modifyvm", :id, "--nictype2", "82543GC"]
     vb.customize ["modifyvm", :id, "--memory", memory]
     vb.customize ["modifyvm", :id, "--vram", vram]
     vb.customize ["modifyvm", :id, "--cpus", cpus]
     vb.customize ["modifyvm", :id, "--largepages", "on"]
     vb.customize ["modifyvm", :id, "--nestedpaging", "on"]
     vb.customize ["modifyvm", :id, "--vtxvpid", "on"]
     vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
     vb.customize ["modifyvm", :id, "--ioapic", "on"]
     #vb.customize ["modifyvm", :id, "--chipset", "ich9"]
   end

end
