#!/bin/sh
# Shared helpers for the setup scripts. Sourced, never executed.

: "${ROOT:?ROOT must be set before sourcing lib/common.sh}"

if [ -t 1 ]; then
    C_RED=$(printf '\033[31m'); C_GRN=$(printf '\033[32m')
    C_YEL=$(printf '\033[33m'); C_DIM=$(printf '\033[2m'); C_OFF=$(printf '\033[0m')
else
    C_RED=; C_GRN=; C_YEL=; C_DIM=; C_OFF=
fi

log()  { printf '%s==%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
step() { printf '%s-->%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$C_GRN" "$C_OFF" "$*"; }

# Path of the running scripts' repository root (independent of CWD).
repo_root() {
    CDPATH= cd -- "$(dirname -- "$1")/.." && pwd
}

# Replace the collecting user's home with a placeholder that install.sh renders.
sanitize_home_paths() {
    _file=$1
    [ -f "$_file" ] || return 0
    # Файл без пути пользователя не переписываем: иначе меняются переводы строк
    # и права лицензионных файлов третьих сторон.
    grep -qIs "/home/${COLLECT_USER}" "$_file" || return 0
    sed -i "s|/home/${COLLECT_USER}|@HOME@|g" "$_file"
}

# Remove the [user] section from a git config so no identity travels along.
strip_git_identity() {
    _file=$1
    [ -f "$_file" ] || return 0
    awk '
        /^[[:space:]]*\[/ {
            section = $0
            gsub(/[[:space:]\[\]]/, "", section)
            skip = (section == "user")
        }
        !skip { print }
    ' "$_file" > "$_file.tmp" && mv "$_file.tmp" "$_file"
}

# Drop lines matching a pattern from a file (dead desktop entries and the like).
drop_lines_matching() {
    _file=$1; _pattern=$2
    [ -f "$_file" ] || return 0
    grep -vE "$_pattern" "$_file" > "$_file.tmp" || true
    mv "$_file.tmp" "$_file"
}

# Grow a newline-separated list without duplicates.
list_add() {
    _list=$1; _item=$2
    case ":$_list:" in *":$_item:"*) return 0 ;; esac
    printf '%s\n' "$_item"
}
