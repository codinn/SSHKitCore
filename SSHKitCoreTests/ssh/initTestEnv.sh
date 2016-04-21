#!/bin/sh

#  initTestEnv.sh
#  SSHKitCore
#
#  Created by vicalloy on 2/5/16.
#

# https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/dscl.1.html

# Create user sshtest for single-factor authentication
sudo ./osx-adduser.sh sshtest "SSH Test" "v#.%-dzd"
sudo mkdir -p /Users/sshtest/.ssh
sudo sh -c "cat ./ssh_rsa_key.pub >> /Users/sshtest/.ssh/authorized_keys"
sudo chmod -R 700 /Users/sshtest/.ssh
sudo chown -R sshtest:staff /Users/sshtest/

# Create user sshtest-m for multi-factor authentication purpose
sudo ./osx-adduser.sh sshtest-m "SSH Test Multi" "v#.%-dzd"
sudo mkdir -p /Users/sshtest-m/.ssh
sudo sh -c "cat ./ssh_rsa_key.pub >> /Users/sshtest-m/.ssh/authorized_keys"
sudo chmod -R 700 /Users/sshtest-m/.ssh
sudo chown -R sshtest-m:staff /Users/sshtest-m/

# Create user sshtest-nopass for testing password auth disabled
sudo ./osx-adduser.sh sshtest-nopass "SSH Test NoPass" "v#.%-dzd"
sudo mkdir -p /Users/sshtest-nopass/.ssh
sudo sh -c "cat ./ssh_rsa_key.pub >> /Users/sshtest-nopass/.ssh/authorized_keys"
sudo chmod -R 700 /Users/sshtest-nopass/.ssh
sudo chown -R sshtest-m:staff /Users/sshtest-nopass/

echo "
!! Please copy following text to the end of your /etc/ssh/sshd_config file!!

Match User sshtest
	PasswordAuthentication yes

Match User sshtest-m
	PasswordAuthentication yes
	AuthenticationMethods publickey,keyboard-interactive,password,keyboard-interactive,publickey

Match User sshtest-nopass
	PasswordAuthentication no
"
