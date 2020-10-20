#!/usr/bin/env bash

set -e

dhclient="sudo dhclient -pf /var/run/dhclient.pid -lf /var/run/dhclient.lease"
wpa_supplicant="sudo wpa_supplicant -B -P /var/run/wpa_supplicant.pid -i wlp3s0 -c /home/gerard/.config/wpa.conf"

sudo killall wpa_supplicant || true;
sudo killall dhclient || true;
sudo ip route del default || true;

if [ "$1" == "wifi" ]; then
	if [ -f "/var/run/wpa_supplicant.pid" ]; then
		sudo kill $(cat /var/run/wpa_supplicant.pid);
	fi
	$wpa_supplicant;
	while [ "$(sudo ifconfig | grep wlp3s0 )" == "" ]; do
		sleep .5;
		echo -n "."
	done;
	echo ""
	$dhclient wlp3s0
elif [ "$1" == "eth" ]; then
	$dhclient enp0s31f6
fi
