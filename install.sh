#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── single-file symlinks into $HOME ──────────────────────────────────────────
declare -A links

links[".gitconfig"]="gitconfig"
links[".config/i3/config"]="i3-config"
links[".config/i3status/config"]="i3status.conf"
links[".vimrc"]="vimrc"
links[".xinitc"]="xinitrc"
links[".bash_aliases"]="bash_aliases"

for f in screenlayout/*.sh; do
    links[".${f}"]="$f"
done

for k in "${!links[@]}"; do
    mkdir -p "$(dirname "$HOME/${k}")"
    ln -sfv "$ROOT/${links[$k]}" "$HOME/${k}"
done

# ── bin/* → ~/bin/* ──────────────────────────────────────────────────────────
mkdir -p "$HOME/bin"
for f in "$ROOT"/bin/*; do
    [ -f "$f" ] || continue
    ln -sfv "$f" "$HOME/bin/$(basename "$f")"
done

# ── systemd/user/* → ~/.config/systemd/user/* ────────────────────────────────
mkdir -p "$HOME/.config/systemd/user"
for f in "$ROOT"/systemd/user/*; do
    [ -f "$f" ] || continue
    ln -sfv "$f" "$HOME/.config/systemd/user/$(basename "$f")"
done

# Reload + enable any user timers we shipped. Best-effort: only meaningful if
# systemd --user is running (i.e. you're on a real desktop session, not in a
# remote ssh without lingering enabled).
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-units >/dev/null 2>&1; then
    systemctl --user daemon-reload
    for unit in "$ROOT"/systemd/user/*.timer; do
        [ -f "$unit" ] || continue
        name="$(basename "$unit")"
        systemctl --user enable --now "$name" \
            && echo "  enabled+started: $name (user)" \
            || echo "  WARN: failed to enable $name — start manually"
    done
else
    echo ""
    echo "NOTE: systemd --user not reachable (no graphical session, or lingering disabled)."
    echo "      Run inside your i3 session, or enable lingering: loginctl enable-linger \$USER"
fi

# ── manual one-shot (as root, once) ──────────────────────────────────────────
if ! id -nG | grep -qw systemd-journal; then
    cat <<EOF

NOTE: $USER is not in 'systemd-journal' — fs-watch-status can't see
      system journal lines. Run once as root, then log out + back in:
          usermod -aG systemd-journal $USER
EOF
fi

# chromium hangs ~25s at first navigation while it probes for a Secret
# Service backend that isn't there. Drop a /etc/chromium.d/ snippet that
# pre-sets --password-store=basic so chromium skips the probe.
if [ ! -f /etc/chromium.d/password-store ]; then
    cat <<EOF

NOTE: /etc/chromium.d/password-store is missing
      (causes ~25s chromium startup hang). Run once as root:
          su -c "install -m 644 $ROOT/etc/chromium.d/password-store /etc/chromium.d/"
EOF
fi
