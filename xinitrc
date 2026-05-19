( sleep 2 && enable_natural_scroll );
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
exec i3
