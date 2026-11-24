#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
link="$HOME/.config/goto/goto.sh"
bashrc="$HOME/.bashrc"
dirs="$HOME/.goto_dirs"
source_line='. "$HOME/.config/goto/goto.sh"'

mkdir -p "$(dirname "$link")"
ln -sfn "$repo/goto.sh" "$link"
echo "linked $link → $repo/goto.sh"

touch "$bashrc"
if grep -qxF "$source_line" "$bashrc"; then
    echo "$bashrc already sources goto"
else
    printf '\n%s\n' "$source_line" >> "$bashrc"
    echo "added source line to $bashrc"
fi

if [ -e "$dirs" ]; then
    echo "$dirs already exists, left as is"
else
    while IFS='=' read -r name dir; do
        if [ -d "${dir/#\~/$HOME}" ]; then printf '%s=%s\n' "$name" "$dir"; fi
    done < "$repo/dirs.example" > "$dirs"
    echo "created $dirs from the dirs.example entries that exist here"
fi
