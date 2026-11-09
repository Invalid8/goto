GOTO_FILE="$HOME/.goto_dirs"
GOTO_HISTORY="$HOME/.goto_history"
GOTO_ROOTS=("$HOME/Projects")
GOTO_SEARCH_DEPTH=2
GOTO_HISTORY_LIMIT=1000
GOTO_RECENT_COUNT=15
GOTO_COMMANDS="add rm ls recent code zed edit help"

touch "$GOTO_FILE" "$GOTO_HISTORY"

_goto_expand() { printf '%s\n' "${1/#\~/$HOME}"; }
_goto_shorten() { printf '%s\n' "${1/#$HOME/\~}"; }
_goto_names() { cut -d= -f1 "$GOTO_FILE"; }

_goto_lookup() {
    awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$GOTO_FILE"
}

_goto_candidates() {
    awk -v home="$HOME" '{
        i = index($0, "=")
        if (i < 2) next
        dir = substr($0, i + 1)
        if (substr(dir, 1, 1) == "~") dir = home substr(dir, 2)
        print substr($0, 1, i - 1) "\t" dir
    }' "$GOTO_FILE"
    find "${GOTO_ROOTS[@]}" -mindepth 1 -maxdepth $((GOTO_SEARCH_DEPTH + 2)) \
        -name .git -printf 'repo\t\t%h\n' -prune -o \
        \( -name node_modules -o -name '.*' \) -prune -o \
        -printf '%d\t%y\t%p\n' 2>/dev/null |
        awk -F'\t' -v max="$GOTO_SEARCH_DEPTH" '
            function emit(dir,    name) { name = dir; sub(/.*\//, "", name); print name "\t" dir }
            $1 == "repo" { repo[$3] = 1; next }
            $1 <= max { if ($2 == "d") emit($3); next }
            $1 == max + 1 {
                parent = $3; sub(/\/[^\/]*$/, "", parent)
                if ($2 == "d") inner[$3] = parent; else has_files[parent] = 1
            }
            END { for (dir in inner) if (dir in repo || !(inner[dir] in has_files)) emit(dir) }'
}

_goto_matches() {
    _goto_candidates | awk -F'\t' -v q="${1,,}" '
        function near(a, b,    i) {
            i = 1
            while (i <= length(a) && substr(a, i, 1) == substr(b, i, 1)) i++
            return substr(a, i + 1) == substr(b, i + 1) ||
                substr(a, i) == substr(b, i + 1) ||
                substr(a, i + 1) == substr(b, i) ||
                (substr(a, i, 1) == substr(b, i + 1, 1) && substr(a, i + 1, 1) == substr(b, i, 1) &&
                    substr(a, i + 2) == substr(b, i + 2))
        }
        function scattered(name,    i, j) {
            j = 1
            for (i = 1; i <= length(name) && j <= length(q); i++)
                if (substr(name, i, 1) == substr(q, j, 1)) j++
            return j > length(q) && substr(name, 1, 1) == substr(q, 1, 1)
        }
        function stage(name) {
            if (name == q) return 1
            if (index(name, q) == 1) return 2
            if (index(name, q)) return 3
            if (length(q) < 3) return 0
            if (near(name, q)) return 4
            if (scattered(name)) return 5
            return 0
        }
        {
            found = stage(tolower($1))
            if (!found) next
            if (!best || found < best) best = found
            stages[++n] = found; dirs[n] = $2
        }
        END { for (i = 1; i <= n; i++) if (stages[i] == best && !seen[dirs[i]]++) print dirs[i] }' |
        _goto_rank
}

_goto_rank() {
    awk -v hist="$GOTO_HISTORY" '
        BEGIN { while ((getline line < hist) > 0) visits[line]++ }
        { printf "%d\t%d\t%s\n", visits[$0], NR, $0 }' |
        sort -t$'\t' -k1,1nr -k2,2n | cut -f3-
}

_goto_pick() {
    local dir choice="" options=()
    if [ $# -eq 1 ]; then
        _GOTO_DEST="$1"
        return 0
    fi
    for dir in "$@"; do options+=("$(_goto_shorten "$dir")"); done
    local PS3="goto> "
    select choice in "${options[@]}"; do
        [ -n "$choice" ] && break
    done
    [ -n "$choice" ] || return 1
    _GOTO_DEST=$(_goto_expand "$choice")
}

_goto_resolve() {
    local dest matches
    dest=$(_goto_lookup "$1")
    if [ -n "$dest" ]; then
        _GOTO_DEST=$(_goto_expand "$dest")
        return 0
    fi
    mapfile -t matches < <(_goto_matches "$1")
    if [ ${#matches[@]} -eq 0 ]; then
        echo "goto: nothing matches '$1'" >&2
        return 1
    fi
    _goto_pick "${matches[@]}"
}

_goto_record() {
    printf '%s\n' "$PWD" >> "$GOTO_HISTORY"
    if [ "$(wc -l < "$GOTO_HISTORY")" -gt "$GOTO_HISTORY_LIMIT" ]; then
        local tmp
        tmp=$(mktemp)
        tail -n "$GOTO_HISTORY_LIMIT" "$GOTO_HISTORY" > "$tmp" && mv "$tmp" "$GOTO_HISTORY"
    fi
}

_goto_jump() {
    _goto_resolve "$1" && cd "$_GOTO_DEST${2:+/$2}" && _goto_record
}

_goto_list() {
    sort -t= -k2 "$GOTO_FILE" | while IFS='=' read -r name dir; do
        printf '  \e[1m%-16s\e[0m %s\n' "$name" "$dir"
    done
    printf '\n  Any folder under %s also works by name.\n' "$(_goto_shorten "${GOTO_ROOTS[*]}")"
}

_goto_add() {
    local name="$1" dir
    if [ -z "$name" ]; then
        echo "usage: goto add <name> [dir]" >&2
        return 1
    fi
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]] || [[ " $GOTO_COMMANDS " == *" $name "* ]]; then
        echo "goto: '$name' can't be a shortcut name" >&2
        return 1
    fi
    if ! dir=$(cd "${2:-$PWD}" 2>/dev/null && pwd); then
        echo "goto: no such directory '$2'" >&2
        return 1
    fi
    [ -n "$(_goto_lookup "$name")" ] && _goto_rm "$name"
    printf '%s=%s\n' "$name" "$(_goto_shorten "$dir")" >> "$GOTO_FILE"
    echo "$name → $(_goto_shorten "$dir")"
}

_goto_rm() {
    if [ -z "$(_goto_lookup "$1")" ]; then
        echo "goto: no shortcut '$1'" >&2
        return 1
    fi
    local tmp
    tmp=$(mktemp)
    awk -v k="$1" 'index($0, k "=") != 1' "$GOTO_FILE" > "$tmp" && mv "$tmp" "$GOTO_FILE"
}

_goto_recent() {
    local dir recent
    mapfile -t recent < <(
        tac "$GOTO_HISTORY" | awk '!seen[$0]++' | while IFS= read -r dir; do
            [ -d "$dir" ] && printf '%s\n' "$dir"
        done | head -n "$GOTO_RECENT_COUNT"
    )
    if [ ${#recent[@]} -eq 0 ]; then
        echo "goto: no history yet" >&2
        return 1
    fi
    _goto_pick "${recent[@]}" && cd "$_GOTO_DEST" && _goto_record
}

_goto_help() {
    cat <<'EOF'
goto <name> [subdir]   jump to a shortcut or any project folder (prefix/partial names work)
goto                   list shortcuts
goto add <name> [dir]  save a shortcut (defaults to the current folder)
goto rm <name>         remove a shortcut
goto recent            pick from recently visited folders
goto code <name>       jump and open in VS Code
goto zed <name>        jump and open in Zed
goto edit              edit the shortcut file
EOF
}

goto() {
    case "$1" in
        "" | ls) _goto_list ;;
        add) _goto_add "$2" "$3" ;;
        rm) _goto_rm "$2" ;;
        recent) _goto_recent ;;
        code | zed)
            local editor="$1"
            shift
            _goto_jump "$@" && "$editor" .
            ;;
        edit) "${EDITOR:-nano}" "$GOTO_FILE" ;;
        help | -h | --help) _goto_help ;;
        *) _goto_jump "$@" ;;
    esac
}

_goto_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}" first="${COMP_WORDS[1]}" base
    local targets
    targets="$(_goto_candidates | cut -f1 | sort -u)"
    case "$COMP_CWORD:$first" in
        1:*) mapfile -t COMPREPLY < <(compgen -W "$GOTO_COMMANDS $targets" -- "$cur") ;;
        2:rm) mapfile -t COMPREPLY < <(compgen -W "$(_goto_names)" -- "$cur") ;;
        2:code | 2:zed) mapfile -t COMPREPLY < <(compgen -W "$targets" -- "$cur") ;;
        3:add) mapfile -t COMPREPLY < <(compgen -d -- "$cur") ;;
        2:*)
            base=$(_goto_expand "$(_goto_lookup "$first")")
            [ -n "$base" ] || base=$(_goto_matches "$first" | head -n 1)
            [ -n "$base" ] || return
            compopt -o nospace
            mapfile -t COMPREPLY < <(cd "$base" 2>/dev/null && compgen -d -S / -- "$cur")
            ;;
    esac
}
complete -F _goto_complete goto
