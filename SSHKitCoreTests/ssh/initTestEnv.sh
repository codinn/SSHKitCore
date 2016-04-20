#!/bin/sh

#  initTestEnv.sh
#  SSHKitCore
#
#  Created by vicalloy on 2/5/16.
#

# https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/dscl.1.html
# create user sshtest
sudo ./osx-adduser.sh sshtest "SSH Test" "v#.%-dzd"
sudo mkdir -p /Users/sshtest/.ssh
sudo sh -c "cat ./ssh/ssh_host_rsa_key.pub >> /Users/sshtest/.ssh/authorized_keys"
sudo chmod -R 700 /Users/sshtest/.ssh
sudo chown -R sshtest:staff /Users/sshtest/
# vim /etc/ssh/sshd_config
