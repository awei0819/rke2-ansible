#!/bin/bash
ssh_key="ssh_key"
mkdir -p /root/.ssh
echo "$ssh_key" >>/root/.ssh/authorized_keys