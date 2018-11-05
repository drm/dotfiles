enable_natural_scroll() {
	local devid="`xinput | grep TouchPad | egrep -o 'id=[0-9]+' | cut -c 4-`"
	local propid="`xinput list-props $devid | grep Natural | grep -v 'Default' | egrep -o '\([0-9]+\)' | tr -d '()'`"

	xinput set-prop $devid $propid 1
}

(sleep 2 && xscreensaver -no-splash )&
(sleep 2 && $HOME/.dropbox-dist/dropboxd )&
(sleep 2 && enable_natural_scroll) &
exec i3
