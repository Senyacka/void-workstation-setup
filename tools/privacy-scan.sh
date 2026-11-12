#!/bin/sh
# privacy-scan - fail when personal data or secrets leak into the repository.
#
# Rules come from privacy/patterns.txt (universal, safe to commit), from the
# current session (login, hostname, git identity - never stored) and from
# ~/.config/workstation-setup/privacy.local (private, outside the repository).
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
PATTERNS=${PRIVACY_PATTERNS:-$ROOT/privacy/patterns.txt}
ALLOWED=${PRIVACY_ALLOWED:-$ROOT/privacy/allowed.txt}
LOCAL_PATTERNS=${PRIVACY_LOCAL:-${XDG_CONFIG_HOME:-$HOME/.config}/workstation-setup/privacy.local}

quiet=0; show=0; paths=

usage() {
    cat <<'USAGE'
usage: privacy-scan.sh [options] [paths...]
  --quiet   exit status only
  --show    print the offending line (masked)
  --rules   print the active rule set and exit
USAGE
}

while [ $# -gt 0 ]; do
    case $1 in
        --quiet) quiet=1 ;;
        --show) show=1 ;;
        --rules) show_rules=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) usage >&2; exit 2 ;;
        *) paths="$paths $1" ;;
    esac
    shift
done

[ -n "$paths" ] || paths=$ROOT

escape_re() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|/]/\\&/g'
}

collect_rules() {
    [ -r "$PATTERNS" ] || { echo "privacy-scan: нет $PATTERNS" >&2; exit 2; }
    grep -v '^[[:space:]]*#' "$PATTERNS" | grep -v '^[[:space:]]*$' || true

    for value in "$(id -un 2>/dev/null || echo)" \
                 "$(hostname 2>/dev/null || echo)" \
                 "$(git -C "$ROOT" config --get user.email 2>/dev/null || echo)" \
                 "$(git -C "$ROOT" config --get user.name 2>/dev/null || echo)"; do
        [ -n "$value" ] || continue
        [ ${#value} -ge 3 ] || continue
        printf 'current session value\t%s\n' "$(escape_re "$value")"
    done

    if [ -r "$LOCAL_PATTERNS" ]; then
        grep -v '^[[:space:]]*#' "$LOCAL_PATTERNS" | grep -v '^[[:space:]]*$' || true
    fi
}

rules=$(collect_rules)

if [ "${show_rules:-0}" = 1 ]; then
    printf '%s\n' "$rules"
    exit 0
fi

# Placeholders that are meant to be committed must not be reported.
SKIP='(/home/(user|username|<user>|\$USER|%u)|@HOME@|/home/@@)'

findings=0
files_hit=0
report=

for dir in $paths; do
    [ -d "$dir" ] || continue
    while IFS=$(printf '\t') read -r label regexp; do
        [ -n "${regexp:-}" ] || continue
        hits=$(grep -rInE --binary-files=without-match \
                 --exclude-dir=.git \
                 --exclude-dir=state \
                 --exclude-dir=.collect \
                 --exclude-dir=profiles \
                 --exclude=patterns.txt \
                 --exclude=allowed.txt \
                 --exclude=privacy-scan.sh \
                 -- "$regexp" "$dir" 2>/dev/null | grep -vE "$SKIP" || true)
        if [ -n "$hits" ] && [ -r "$ALLOWED" ]; then
            allow=$(grep -v '^[[:space:]]*#' "$ALLOWED" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')
            [ -n "$allow" ] && hits=$(printf '%s\n' "$hits" | grep -vE "$allow" || true)
        fi
        [ -n "$hits" ] || continue
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            file=${hit%%:*}
            rest=${hit#*:}
            line=${rest%%:*}
            findings=$((findings + 1))
            report="$report
$file:$line  $label"
            if [ "$show" = 1 ]; then
                text=${rest#*:}
                report="$report
    $(printf '%s' "$text" | cut -c1-100)"
            fi
        done <<EOF_HITS
$hits
EOF_HITS
    done <<EOF_RULES
$rules
EOF_RULES
done

if [ "$findings" -eq 0 ]; then
    [ "$quiet" = 1 ] || printf 'privacy-scan: 0 вхождений\n'
    exit 0
fi

files_hit=$(printf '%s\n' "$report" | grep -c ':[0-9]*\s' || true)
[ "$quiet" = 1 ] || printf 'privacy-scan: %s совпадений\n%s\n' "$findings" "$report"
exit 1
