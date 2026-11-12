#!/bin/sh
# verify.sh - compare this machine with what the configuration expects.
# Read-only: prints a report and returns 0 when nothing is missing.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR" && pwd)
. "$ROOT/lib/common.sh"

CONFIG=${XDG_STATE_HOME:-$HOME/.local/state}/void-workstation/applied.conf
[ $# -gt 0 ] && case $1 in --config) CONFIG=${2:?} ;; esac
[ -r "$CONFIG" ] || { warn "нет $CONFIG: сначала выполни install.sh"; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG"

missing=0
check_file() {
    if [ -e "$1" ]; then ok "$2"; else printf '  %s[--]%s %s\n' "$C_YEL" "$C_OFF" "$2"; missing=$((missing + 1)); fi
}
check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then ok "${2:-$1}"; else printf '  %s[--]%s %s\n' "$C_YEL" "$C_OFF" "${2:-$1}"; missing=$((missing + 1)); fi
}

step "файлы конфигурации"
while IFS=$(printf '\t') read -r path kind base sha; do
    case $kind in ours|unowned) ;; *) continue ;; esac
    check_file "$path" "$path"
done < "$ROOT/system/MANIFEST"

step "домашний каталог"
for rel in .config/niri/config.kdl .config/dms/settings.json .config/kitty/kitty.conf \
           .local/bin/healthcheck .local/bin/theme-sync .local/bin/start-session-audio \
           .config/service/pipewire/run .config/gtk-3.0/settings.ini; do
    check_file "$TARGET_HOME/$rel" "~/$rel"
done

step "пакеты"
absent=$(for pkg in $PACKAGES; do
             xbps-query -p pkgver "$pkg" >/dev/null 2>&1 || printf '%s ' "$pkg"
         done)
if [ -n "$absent" ]; then
    printf '  %s[--]%s не установлены: %s\n' "$C_YEL" "$C_OFF" "$absent"
    missing=$((missing + 1))
else
    ok "все пакеты из конфигурации установлены"
fi

step "сервисы"
for svc in NetworkManager udevd dbus seatd greetd; do
    if [ -e "/var/service/$svc" ]; then ok "$svc включён"; else
        printf '  %s[--]%s %s не включён\n' "$C_YEL" "$C_OFF" "$svc"; missing=$((missing + 1))
    fi
done

step "сессия и вид"
command -v niri >/dev/null 2>&1 && niri validate -c "$TARGET_HOME/.config/niri/config.kdl" \
    && ok "конфиг niri валиден" || { printf '  %s[--]%s niri validate не прошёл\n' "$C_YEL" "$C_OFF"; missing=$((missing + 1)); }
if fc-list 2>/dev/null | grep -qi 'FiraCode Nerd'; then ok "шрифт FiraCode Nerd Font на месте"; else
    printf '  %s[--]%s нет FiraCode Nerd Font\n' "$C_YEL" "$C_OFF"; missing=$((missing + 1))
fi
check_file "$TARGET_HOME/.local/share/themes/adw-gtk3-dark/gtk-3.0/gtk.css" "тема adw-gtk3-dark"
check_cmd dms "шелл dms"
check_cmd qs "quickshell"

printf '\n'
if [ "$missing" -eq 0 ]; then
    ok "расхождений нет"
    exit 0
fi
warn "расхождений: $missing"
exit 1
