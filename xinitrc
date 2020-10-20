xrdb -merge -I$HOME ~/.Xresources
(sleep 2 && xscreensaver -no-splash )&
(sleep 2 && enable_natural_scroll) &
(sleep 2 && setxbmap -option compose:ralt) &
exec i3
