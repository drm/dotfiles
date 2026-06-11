#!/usr/bin/env bash

set -e

IFACE=wlp3s0
CONF_DIR="$HOME/.config/wpa"

dhclient="sudo dhclient -pf /var/run/dhclient.pid -lf /var/run/dhclient.lease"

mkdir -p "$CONF_DIR"

usage() {
	echo "Usage: $0 wifi [name]   connect to a saved wifi network (first saved if no name)"
	echo "       $0 add           scan, enter a password and save a new network"
	echo "       $0 eth           connect via ethernet"
	exit 1
}

teardown() {
	sudo killall wpa_supplicant || true
	sudo killall dhclient || true
	sudo ip route del default || true
	sudo rm -f "/var/run/wpa_supplicant/$IFACE"
}

list_configs() {
	find "$CONF_DIR" -maxdepth 1 -name '*.conf' -printf '%f\n' 2>/dev/null | sed 's/\.conf$//' | sort
}

config_ssid() {
	sed -n 's/^[[:space:]]*ssid="\(.*\)"$/\1/p' "$CONF_DIR/$1.conf"
}

scan_ssids() {
	sudo ip link set "$IFACE" up
	sudo iw dev "$IFACE" scan | sed -n 's/^[[:space:]]*SSID: //p' | grep -v '^$' | sort -u
}

slugify() {
	echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//'
}

wired_ifaces() {
	local i name
	for i in /sys/class/net/*; do
		name="${i##*/}"
		[ "$name" = "lo" ] && continue
		[ -d "$i/wireless" ] && continue
		[ -e "$i/device" ] || continue
		echo "$name"
	done
}

detect_eth() {
	local name
	for name in $(wired_ifaces); do
		sudo ip link set "$name" up || true
	done
	sleep 1
	for name in $(wired_ifaces); do
		[ "$(cat "/sys/class/net/$name/carrier" 2>/dev/null)" = "1" ] && { echo "$name"; return 0; }
	done
	return 1
}

connect_eth() {
	teardown
	local iface
	iface="$(detect_eth)" || { echo "No wired interface with a carrier (cable) found."; exit 1; }
	echo "Using $iface"
	sudo ip addr flush dev "$iface"
	$dhclient "$iface"
}

connect_wifi() {
	local name="$1" conf
	if [ -z "$name" ]; then
		echo "Scanning for known networks on $IFACE..."
		local in_range available cfg
		in_range="$(scan_ssids)"
		mapfile -t available < <(
			while read -r cfg; do
				grep -qxF "$(config_ssid "$cfg")" <<<"$in_range" && echo "$cfg"
			done < <(list_configs)
		)
		if [ "${#available[@]}" -eq 0 ]; then
			local reply
			read -r -p "No known networks in range. Add one now? [Y/n] " reply
			case "$reply" in
				[Nn]*) exit 1 ;;
				*) add_network; return ;;
			esac
		elif [ "${#available[@]}" -eq 1 ]; then
			name="${available[0]}"
			echo "Connecting to '$name'"
		else
			echo "Select a network:"
			select name in "${available[@]}"; do
				[ -n "$name" ] && break
			done
		fi
	fi

	conf="$CONF_DIR/$name.conf"
	if [ ! -f "$conf" ]; then
		echo "No saved config for '$name' ($conf)"
		exit 1
	fi

	teardown
	sudo ip link set "$IFACE" up
	sudo wpa_supplicant -B -P /var/run/wpa_supplicant.pid -i "$IFACE" -c "$conf"
	while [ "$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)" != "up" ]; do
		sleep .5
		echo -n "."
	done
	echo ""
	sudo ip addr flush dev "$IFACE"
	$dhclient "$IFACE"
}

add_network() {
	echo "Scanning for networks on $IFACE..."
	local ssids
	mapfile -t ssids < <(scan_ssids)
	if [ "${#ssids[@]}" -eq 0 ]; then
		echo "No networks found."
		exit 1
	fi

	echo "Select a network to add:"
	local ssid
	select ssid in "${ssids[@]}"; do
		[ -n "$ssid" ] && break
	done

	local password
	read -r -s -p "Password for \"$ssid\" (empty for open network): " password
	echo ""

	local default_name name
	default_name="$(slugify "$ssid")"
	read -r -p "Save config as [$default_name]: " name
	name="${name:-$default_name}"

	local conf="$CONF_DIR/$name.conf" psk=""
	[ -n "$password" ] && psk=$(wpa_passphrase "$ssid" "$password" | sed -n 's/^[[:space:]]*psk=//p')
	{
		echo "network={"
		echo "	ssid=\"$ssid\""
		echo "	scan_ssid=1"
		if [ -z "$psk" ]; then
			echo "	key_mgmt=NONE"
		else
			echo "	psk=$psk"
		fi
		echo "}"
	} > "$conf"
	chmod 600 "$conf"
	echo "Saved network '$ssid' as '$name' ($conf)"

	connect_wifi "$name"
}

case "$1" in
	wifi) connect_wifi "$2" ;;
	add)  add_network ;;
	eth)  connect_eth ;;
	*)    usage ;;
esac
