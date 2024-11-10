#!/bin/bash

cd /tmp

# If the file not exists, mean we need to initialize
if [ ! -f /var/lib/zerotier-one/identity.secret ] ; then 
    echo "Zerotier-One Configuration is **NOT** initialized."
    usermod -aG zerotier-one root
    mkdir -p /var/lib/zerotier-one
    rm -rf /var/lib/zerotier-one/*
    ln -sf /usr/sbin/zerotier-one /var/lib/zerotier-one/zerotier-cli
    ln -sf /usr/sbin/zerotier-one /var/lib/zerotier-one/zerotier-idtool
    ln -sf /usr/sbin/zerotier-one /var/lib/zerotier-one/zerotier-one
    chown zerotier-one:zerotier-one /var/lib/zerotier-one    # zerotier-one user home
    #chown -R zerotier-one:zerotier-one /var/lib/zerotier-one  # zerotier-one will change this at runtime. 
else
    echo "Zerotier-One Configuration is initialized."
fi

# zt1 must run as root.
/usr/sbin/zerotier-one
