#!/usr/bin/env bash

set -e

dhclient="dhclient -pf /var/run/dhclient.pid -lf /var/run/dhclient.lease"
wpa_supplicant="wpa_supplicant -B -P /var/run/wpa_supplicant.pid -i wlp3s0 -c ./wpa.conf"

if [ "$1" == "down" ]; then
	killall wpa_supplicant;
	killall dhclient;
elif [ "$1" == "wifi" ]; then
	if [ -f "/var/run/wpa_supplicant.pid" ]; then
		kill $(cat /var/run/wpa_supplicant.pid);
	fi
	$wpa_supplicant;
	while [ "$(ifconfig | grep wlp3s0 )" == "" ]; do
		sleep .5;
		echo -n "."
	done;
	echo ""
	$dhclient wlpi3s0
elif [ "$1" == "eth" ]; then
	$dhclient enp0s31f6
fi
