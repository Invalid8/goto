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

_goto_shortcut_paths() {
    awk -v mode="$1" -v q="${2,,}" '{
        k = tolower(substr($0, 1, index($0, "=") - 1)); i = index(k, q)
        if ((mode == "prefix" && i == 1) || (mode == "contains" && i > 0)) print substr($0, index($0, "=") + 1)
    }' "$GOTO_FILE"
}

_goto_project_dirs() {
    find "${GOTO_ROOTS[@]}" -mindepth 1 -maxdepth "$GOTO_SEARCH_DEPTH" \
        \( -name node_modules -o -name '.*' \) -prune -o -type d -print 2>/dev/null
}

_goto_project_paths() {
    local mode="$1" q="${2,,}" dir base
    _goto_project_dirs | while IFS= read -r dir; do
        base="${dir##*/}"
        base="${base,,}"
        case "$mode" in
            exact) [ "$base" = "$q" ] ;;
            prefix) [[ "$base" == "$q"* ]] ;;
            contains) [[ "$base" == *"$q"* ]] ;;
        esac && printf '%s\n' "$dir"
    done
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
    local q="$1" stage dest matches
    dest=$(_goto_lookup "$q")
    if [ -n "$dest" ]; then
        _GOTO_DEST=$(_goto_expand "$dest")
        return 0
    fi
    for stage in exact prefix contains; do
        mapfile -t matches < <(
            { [ "$stage" = exact ] || _goto_shortcut_paths "$stage" "$q"; _goto_project_paths "$stage" "$q"; } |
                sed "s|^~|$HOME|" | awk '!seen[$0]++' | _goto_rank
        )
        if [ ${#matches[@]} -gt 0 ]; then
            _goto_pick "${matches[@]}"
            return
        fi
    done
    return 1
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
    if ! _goto_resolve "$1"; then
        echo "goto: nothing matches '$1'" >&2
        return 1
    fi
    cd "$_GOTO_DEST${2:+/$2}" && _goto_record
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
    local recent
    mapfile -t recent < <(tac "$GOTO_HISTORY" | awk '!seen[$0]++' | head -n "$GOTO_RECENT_COUNT")
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
    targets="$({ _goto_names; _goto_project_dirs | sed 's|.*/||'; } | sort -u)"
    case "$COMP_CWORD:$first" in
        1:*) mapfile -t COMPREPLY < <(compgen -W "$GOTO_COMMANDS $targets" -- "$cur") ;;
        2:rm) mapfile -t COMPREPLY < <(compgen -W "$(_goto_names)" -- "$cur") ;;
        2:code | 2:zed) mapfile -t COMPREPLY < <(compgen -W "$targets" -- "$cur") ;;
        3:add) mapfile -t COMPREPLY < <(compgen -d -- "$cur") ;;
        2:*)
            base=$(_goto_lookup "$first")
            [ -n "$base" ] || return
            compopt -o nospace
            mapfile -t COMPREPLY < <(cd "$(_goto_expand "$base")" 2>/dev/null && compgen -d -S / -- "$cur")
            ;;
    esac
}
complete -F _goto_complete goto
