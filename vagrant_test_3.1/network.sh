#!/bin/bash

################################################################################
# Copyright (c) 2014, 2015 Genome Research Ltd.
#
# Author: Matthew Rahtz <matthew.rahtz@sanger.ac.uk>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
################################################################################

# Sets up necessary network environment:
# * A bridge onto which container interfaces can be added
# * A DHCP/DNS server with dynamic DNS support
# * iptables rules to workaround various issues with the Vagrant VM setup

set -o errexit

apt-get -y install bridge-utils dnsmasq

# create the bridge to be used for the containers' interfaces
cat > /etc/network/interfaces.d/br0.cfg <<EOF
auto br0
iface br0 inet static
  address 172.16.0.2
  netmask 255.255.255.0
  bridge_ports none
EOF
ifup br0

# set up dnsmasq, so that the hostnames of the created containers
# are visible through DNS
# (normally this would be taken care of by a central DHCP server with
#  dynamic DNS support)
cat > /etc/dnsmasq.conf <<EOF
interface=br0
dhcp-range=172.16.0.10,172.16.0.50,1h
EOF
service dnsmasq restart

# Currently, virtual interfaces don't support checksum offloading;
# when checksum offloading is enabled, as it is by default,
# checksums aren't calculated, and apparently dhcpcd can't handle that:
# https://code.google.com/p/chromium/issues/detail?id=343431
# This isn't an issue when DHCP packets from an outside source,
# but for our VM setup, we have to manually fix the packets.
# (Also see:
#  https://github.com/fgrehm/vagrant-lxc/issues/153
#  https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/1029430)
# Also set up masquerading so that the containers can get internet access
cat > /etc/rc.local <<EOF
#!/bin/bash
iptables -A POSTROUTING -t mangle -p udp --dport 68 -j CHECKSUM --checksum-fill
iptables -t nat -A POSTROUTING -o eth0 --source 172.16.0.0/24 -j MASQUERADE
EOF
/etc/rc.local
