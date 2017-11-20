#!/bin/bash
ETH0="# The primary network interface
auto eth0
iface eth0 inet static
  address 10.0.2.15
  netmask 255.255.255.0
"

echo "$ETH0" > /etc/network/interfaces.d/eth0.cfg
ifdown eth0 && ifup eth0 && killall -TERM dhclient || true
