alias x="startx"

reset_mouse() {
	sudo modprobe -r psmouse
	sleep 1 && sudo modprobe psmouse
	( sleep 3 && touchpad-setup ) &
}

docker-clean() {
	docker ps --format='{{ .Names }}' | xargs docker rm -f
}
