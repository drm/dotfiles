#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -A links

links[".gitconfig"]="gitconfig"
links[".config/i3/config"]="i3-config"
links[".vimrc"]="vimrc"
links[".xinitc"]="xinitrc"
links[".bash_aliases"]="bash_aliases"

for k in "${!links[@]}"; do
	ln -sfv "$ROOT/${links[$k]}" "$HOME/${k}"
done

