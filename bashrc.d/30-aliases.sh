alias x="startx"

function i3mode {
	if [ "$1" == "small" ]; then
		sed -i 's/^font.*/font pango:DejaVu Sans Mono 8/' ~/.config/i3/config && i3-msg reload;
	else
		sed -i 's/^font.*/font pango:DejaVu Sans Mono 13/' ~/.config/i3/config && i3-msg reload;
	fi
}
