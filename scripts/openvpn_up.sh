#!/bin/sh
# Simple up script for OpenVPN
echo "OpenVPN interface $dev is up"
echo "Local IP: $ifconfig_local"
echo "Remote IP: $ifconfig_remote"
# Ensure log directory exists
mkdir -p /logs
echo "$(date): OpenVPN interface $dev is up, Local: $ifconfig_local, Remote: $ifconfig_remote" >> /logs/up.log
