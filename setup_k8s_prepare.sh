#!/bin/bash

echo '###################################################'
echo 'K8s Prepare Setup'
echo '---------------------------------------------------'

# Step 1: Install Kubernetes Servers
# Once the servers are ready, update them.
sudo apt update
sudo apt -y upgrade

# Enabling cgroup v2
sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/g' /etc/default/grub
sudo update-grub

# Enabling CPU, CPUSET, and I/O delegation
sudo mkdir -p /etc/systemd/system/user@.service.d
cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF
sudo systemctl daemon-reload

sleep 5


echo '---------------------------------------------------'
echo 'K8s Prepare Setup DONE'
echo '###################################################'

echo 'Rebooting...'
sudo systemctl reboot
