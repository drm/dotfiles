alias x="startx"

enable_natural_scroll() {
	local devid="`xinput | grep Synaptics | egrep -o 'id=[0-9]+' | cut -c 4-`"
	local propid="`xinput list-props $devid | grep Natural | grep -v 'Default' | egrep -o '\([0-9]+\)' | tr -d '()'`"

	xinput set-prop $devid $propid 1
}

reset_mouse() {
	sudo modprobe -r psmouse
	sleep 1 && sudo modprobe psmouse
	( sleep 3 && enable_natural_scroll ) &
}

docker-clean() {
	docker ps --format='{{ .Names }}' | xargs docker rm -f
}
