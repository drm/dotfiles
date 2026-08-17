( sleep 2 && enable_natural_scroll );
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
# ISO <> key acts as left Shift
xmodmap -e 'keycode 94 = Shift_L' -e 'add Shift = Shift_L'
exec i3
