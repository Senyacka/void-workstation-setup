#!/bin/sh
# Dialog wrappers with a plain-text fallback.
#
# Every function writes its result to stdout; the caller captures it.
# UI_PLAIN=1 forces the fallback (no tty, no dialog, or --plain).

: "${ROOT:?ROOT must be set}"

UI_PLAIN=${UI_PLAIN:-0}
UI_H=${UI_H:-24}
UI_W=${UI_W:-80}

ui_init() {
    if [ "${UI_PLAIN:-0}" = 1 ] || ! command -v dialog >/dev/null 2>&1 || [ ! -t 0 ] || [ ! -t 1 ]; then
        UI_PLAIN=1
        return 0
    fi
    lines=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)
    case $lines in ''|*[!0-9]*) lines=24 ;; esac
    case $cols in ''|*[!0-9]*) cols=80 ;; esac
    [ "$lines" -lt 20 ] && lines=20
    [ "$cols" -lt 70 ] && cols=70
    [ "$cols" -gt 110 ] && cols=110
    UI_H=$lines
    UI_W=$cols
}

dlg() { dialog --title "${UI_TITLE:-$MSG_TITLE}" "$@"; }

ui_msgbox() {
    title=$1; text=$2
    if [ "$UI_PLAIN" = 1 ]; then printf '\n== %s ==\n%s\n' "$title" "$text" >&2; return 0; fi
    dlg --title "$title" --msgbox "$text" "$UI_H" "$UI_W" >&2
}

ui_yesno() {
    title=$1; text=$2; oklabel=${3:-$MSG_NEXT}
    if [ "$UI_PLAIN" = 1 ]; then
        printf '\n== %s ==\n%s\n[y/N] ' "$title" "$text" >&2
        read -r answer || return 1
        case $answer in [yYдД]*) return 0 ;; *) return 1 ;; esac
    fi
    dialog --title "$title" --ok-label "$oklabel" --cancel-label "$MSG_BACK" \
        --yesno "$text" "$UI_H" "$UI_W"
}

# ui_menu <title> <text> <tag> <desc> [<tag> <desc> ...]
ui_menu() {
    title=$1; text=$2; shift 2
    if [ "$UI_PLAIN" = 1 ]; then
        printf '\n== %s ==\n%s\n' "$title" "$text" >&2
        i=1
        set -- "$@"
        for pair in "$@"; do printf '  %s) %s\n' "$i" "$pair" >&2; i=$((i+1)); done
        printf 'номер: ' >&2
        read -r n || return 255
        i=1
        while [ $# -ge 2 ]; do
            [ "$i" = "$n" ] && { printf '%s\n' "$1"; return 0; }
            shift 2; i=$((i+1))
        done
        return 255
    fi
    dialog --title "$title" --ok-label "$MSG_CHOOSE" --cancel-label "$MSG_BACK" \
        --menu "$text" "$UI_H" "$UI_W" "$(( UI_H - 8 ))" "$@"
}

# ui_checklist <title> <text> -- <tag> <item> <status> <help> ...
ui_checklist() {
    title=$1; text=$2; shift 2
    if [ "$UI_PLAIN" = 1 ]; then
        printf '\n== %s ==\n%s\n' "$title" "$text" >&2
        while [ $# -ge 4 ]; do
            printf '  [%s] %s\n' "$3" "$2" >&2
            shift 4
        done
        printf '(в этом режиме галочки берутся из install.conf)' >&2
        return 255
    fi
    dialog --title "$title" --ok-label "$MSG_OK" --cancel-label "$MSG_BACK" \
        --item-help --no-collapse --scrollbar --separate-output \
        --checklist "$text" "$UI_H" "$UI_W" "$(( UI_H - 9 ))" "$@"
}

sh_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"; }

# ui_form <title> <text> <label> <value> [<label> <value> ...]
# Prints one value per line, in the order of the labels.
ui_form() {
    title=$1; text=$2; shift 2
    if [ "$UI_PLAIN" = 1 ]; then
        while [ $# -ge 2 ]; do
            printf '%s [%s]: ' "$1" "$2" >&2
            value=
            read -r value || true
            printf '%s\n' "${value:-$2}"
            shift 2
        done
        return 0
    fi
    cmd="dialog --title $(sh_quote "$title") --ok-label $(sh_quote "$MSG_OK") --cancel-label $(sh_quote "$MSG_BACK") --form $(sh_quote "$text") $UI_H $UI_W $(( UI_H - 8 ))"
    row=1
    while [ $# -ge 2 ]; do
        cmd="$cmd $(sh_quote "$1") $row 1 $(sh_quote "$2") $row 20 40 60"
        shift 2
        row=$((row + 1))
    done
    eval "$cmd"
}

ui_textbox() {
    title=$1; file=$2
    if [ "$UI_PLAIN" = 1 ]; then cat "$file" >&2; return 0; fi
    dialog --title "$title" --ok-label "$MSG_BACK" --textbox "$file" "$UI_H" "$UI_W" >&2
}

# ui_stage <title> <command...> - run a stage, show its output, keep its status.
ui_stage() {
    title=$1; shift
    if [ "$UI_PLAIN" = 1 ]; then
        "$@"
        return $?
    fi
    out=$(mktemp)
    rc=0
    "$@" > "$out" 2>&1 || rc=$?
    dialog --title "$title" --ok-label "$MSG_NEXT" --textbox "$out" "$UI_H" "$UI_W" >&2 || true
    rm -f "$out"
    return "$rc"
}
