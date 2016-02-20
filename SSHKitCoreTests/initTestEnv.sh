#!/bin/sh

#  initTestEnv.sh
#  SSHKitCore
#
#  Created by vicalloy on 2/5/16.
#

# https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/dscl.1.html
# create user sshtest
sudo dscl . -create /Users/sshtest
sudo dscl . create /Users/sshtest UserShell /bin/bash
sudo dscl . create /Users/sshtest RealName "SSH Test"
sudo dscl . create /Users/sshtest UniqueID 503
sudo dscl . create /Users/sshtest PrimaryGroupID 1000
sudo dscl . create /Users/sshtest NFSHomeDirectory /Users/sshtest
sudo dscl . passwd /Users/sshtest v#.%-dzd
sudo mkdir /Users/sshtest
sudo mkdir /Users/sshtest/.ssh
sudo sh -c "cat ./ssh/ssh_host_rsa_key.pub >> /Users/sshtest/.ssh/authorized_keys"
sudo chmod -R 700 /Users/sshtest/.ssh
sudo chown -R sshtest:staff /Users/sshtest/
# vim /etc/ssh/ssh_config
