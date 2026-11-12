#!/bin/sh
# install.sh - apply the collected configuration to this machine.
#
# Runs as the target user and asks sudo for the parts that need root.
# Everything it changes is backed up next to the original as
# <file>.pre-setup.<timestamp>.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR" && pwd)
. "$ROOT/lib/common.sh"
. "$ROOT/lib/hwdetect.sh"

CONFIG=
DRY=0
ONLY=all
GRUB=auto
ASSUME_YES=0
UI_LANG=${UI_LANG:-auto}

usage() {
    cat <<USAGE
usage: install.sh [options]
  --config <file>   settings produced by menu.sh (default: ./install.conf)
  --only <stage>    repos|packages|system|services|home|assets|session|grub|dms|verify
  --dry-run         print what would change, touch nothing
  --grub            regenerate the GRUB menu after changing the cmdline
  --yes             do not ask for confirmation
  -h, --help        this text
USAGE
}

while [ $# -gt 0 ]; do
    case $1 in
        --config) CONFIG=${2:?}; shift ;;
        --only) ONLY=${2:?}; shift ;;
        --dry-run) DRY=1 ;;
        --grub) GRUB=yes ;;
        --yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "неизвестный аргумент: $1" ;;
    esac
    shift
done

if [ "$UI_LANG" = auto ]; then
    case ${LANG:-} in *UTF-8|*utf8|*UTF8) UI_LANG=ru ;; *) UI_LANG=en ;; esac
fi
[ -r "$ROOT/lang/$UI_LANG.sh" ] || UI_LANG=ru
. "$ROOT/lang/$UI_LANG.sh"

if [ -z "$CONFIG" ]; then
    if [ -r "$ROOT/install.conf" ]; then CONFIG=$ROOT/install.conf
    elif [ -r "${XDG_STATE_HOME:-$HOME/.local/state}/void-workstation/menu.conf" ]; then
        CONFIG=${XDG_STATE_HOME:-$HOME/.local/state}/void-workstation/menu.conf
    else die "нет install.conf: запусти menu.sh или укажи --config"
    fi
fi
[ -r "$CONFIG" ] || die "не читается $CONFIG"

# shellcheck disable=SC1090
. "$CONFIG"

: "${TARGET_USER:=$(id -un)}"
: "${TARGET_HOME:=/home/$TARGET_USER}"
: "${HOSTNAME:=void}"
: "${TIMEZONE:=UTC}"
: "${GREETER:=dms}"
: "${PACKAGES:=}"

STAMP=$(date +%Y%m%d-%H%M%S)
LOG=/tmp/workstation-setup-$STAMP.log
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/void-workstation
STATE_OUT=$STATE_DIR/applied.conf
mkdir -p "$STATE_DIR"

run() {
    if [ "$DRY" = 1 ]; then
        printf '   %s%s%s\n' "$C_DIM" "$*" "$C_OFF"
        return 0
    fi
    "$@"
}

need_root() { sudo -n true 2>/dev/null || die "$MSG_NEED_ROOT"; }

backup() {
    file=$1
    [ -e "$file" ] || return 0
    run sudo cp -a "$file" "$file.pre-setup.$STAMP"
}

render() {
    src=$1; dst=$2
    if [ "$DRY" = 1 ]; then printf '   render %s -> %s\n' "$src" "$dst"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    sed -e "s|@HOME@|$TARGET_HOME|g" \
        -e "s|@USER@|$TARGET_USER|g" \
        -e "s|@HOST@|$HOSTNAME|g" \
        -e "s|@TIMEZONE@|$TIMEZONE|g" "$src" > "$dst"
}

stage_repos() {
    step "репозитории xbps"
    need_root
    while IFS=$(printf '\t') read -r path kind base sha; do
        case $path in /etc/xbps.d/*) ;; *) continue ;; esac
        [ -f "$ROOT/system/root$path" ] || continue
        backup "$path"
        render "$ROOT/system/root$path" "/tmp/xbps-conf.$$"
        run sudo install -m 644 "/tmp/xbps-conf.$$" "$path"
    done < "$ROOT/system/MANIFEST"
    run sudo xbps-install -Sy
}

stage_packages() {
    step "пакеты"
    need_root
    set --
    chosen=$PACKAGES
    case " ${HW_CPU:-} ${HW_GPUS:-} " in *intel*) chosen="$chosen $(sed 's/#.*//' "$ROOT/packages/hardware-intel.txt" | tr -d ' \t' | grep -v '^$' | tr '\n' ' ')" ;; esac
    case " ${HW_CPU:-} ${HW_GPUS:-} " in *amd*) chosen="$chosen $(sed 's/#.*//' "$ROOT/packages/hardware-amd.txt" | tr -d ' \t' | grep -v '^$' | tr '\n' ' ')" ;; esac
    if printf '%s' "$chosen" | grep -qw nvidia; then
        chosen="$chosen $(sed 's/#.*//' "$ROOT/packages/hardware-nvidia.txt" | tr -d ' \t' | grep -v '^$' | tr '\n' ' ')"
    fi
    [ -n "$chosen" ] || { warn "список пакетов пуст"; return 0; }
    run sudo xbps-install -Sy $chosen
}

stage_system() {
    step "файлы в /etc"
    need_root
    while IFS=$(printf '\t') read -r path kind base sha; do
        case $kind in ours|unowned) ;; *) continue ;; esac
        src=$ROOT/system/root$path
        [ -f "$src" ] || { warn "нет $src"; continue; }
        backup "$path"
        render "$src" "/tmp/system-file.$$"
        mode=644
        case $path in /usr/local/sbin/*) mode=755 ;; esac
        [ -e "$path" ] && mode=$(stat -c %a "$path" 2>/dev/null || echo "$mode")
        run sudo install -m "$mode" "/tmp/system-file.$$" "$path"
    done < "$ROOT/system/MANIFEST"
    rm -f "/tmp/system-file.$$" "/tmp/xbps-conf.$$"
    run sudo hostnamectl 2>/dev/null || true
    run sudo ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    run printf '%s\n' "$HOSTNAME" | sudo tee /etc/hostname >/dev/null
}

stage_services() {
    step "сервисы runit"
    need_root
    for svc in NetworkManager acpid bluetoothd chronyd dbus fstrim polkitd \
               power-profiles-daemon rtkit seatd sshd udevd; do
        [ -d "/etc/sv/$svc" ] || continue
        run sudo ln -sfn "/etc/sv/$svc" "/var/service/$svc"
    done
    case "${GROUP_DOCKER:-off}" in
        on) run sudo ln -sfn /etc/sv/docker /var/service/docker ;;
        *)  run sudo rm -f /var/service/docker ;;
    esac
}

stage_home() {
    step "конфигурация в $TARGET_HOME"
    [ "$(id -u)" = "$(id -u "$TARGET_USER")" ] || die "запусти от имени $TARGET_USER"
    find "$ROOT/home" -type f -print | while IFS= read -r src; do
        rel=${src#"$ROOT/home/"}
        case $rel in dconf/*) continue ;; esac
        dst=$TARGET_HOME/$rel
        [ -e "$dst" ] && backup "$dst"
        render "$src" "$dst"
        case $rel in .local/bin/*) run chmod 755 "$dst" ;; esac
    done
    if [ -f "$ROOT/home/dconf/workstation.ini" ] && command -v dconf >/dev/null 2>&1; then
        run dconf load / < "$ROOT/home/dconf/workstation.ini"
    fi
    run fc-cache -f >/dev/null 2>&1 || true
}

stage_assets() {
    step "обои и заставка"
    if [ -d "$ROOT/assets/lockscreen" ]; then
        mkdir -p "$TARGET_HOME/Videos/lockscreen"
        for file in "$ROOT/assets/lockscreen"/*.mp4; do
            [ -f "$file" ] || continue
            run cp -a "$file" "$TARGET_HOME/Videos/lockscreen/"
        done
    fi
}

stage_session() {
    step "вход в систему: greetd ($GREETER)"
    need_root
    conf=/etc/greetd/config.toml
    backup "$conf"
    if [ "$DRY" = 1 ]; then
        printf '   настроить %s для %s\n' "$conf" "$GREETER"
    else
        case $GREETER in
            dms) command='dms-greeter --command niri' ;;
            *)   command="tuigreet --time --cmd 'dbus-run-session niri'" ;;
        esac
        sudo tee "$conf" >/dev/null <<EOF
[terminal]
vt = 7

[default_session]
command = "$command"
user = "_greeter"
EOF
    fi
    run sudo ln -sfn /etc/sv/greetd /var/service/greetd
    # автологин из профиля больше не нужен
    if [ -f "$TARGET_HOME/.bash_profile" ] && [ "$DRY" = 0 ]; then
        awk '/^# Автозапуск Niri/.{skip=1} skip && /^fi$/ {skip=0; next} !skip' \
            "$TARGET_HOME/.bash_profile" > "$TARGET_HOME/.bash_profile.new" || true
        [ -s "$TARGET_HOME/.bash_profile.new" ] && mv "$TARGET_HOME/.bash_profile.new" "$TARGET_HOME/.bash_profile"
    fi
}

stage_grub() {
    step "параметры ядра"
    need_root
    base="quiet loglevel=4 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20 preempt=full nowatchdog"
    extra=
    case ${HW_CPU:-} in amd) extra="$extra amd_pstate=active" ;; esac
    case ${HW_GPU_IDS:-} in *7d51*) extra="$extra i915.force_probe=!7d51 xe.force_probe=7d51" ;; esac
    if printf '%s' "${PACKAGES:-}" | grep -qw nvidia; then
        extra="$extra nvidia-drm.modeset=1 nvidia_drm.fbdev=1"
    fi
    cmdline="$base$extra"
    if [ "$DRY" = 1 ]; then
        printf '   GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$cmdline"
    else
        backup /etc/default/grub
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" /etc/default/grub
    fi
    if [ "$GRUB" = yes ]; then
        run sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        log "меню GRUB не перегенерировано (добавь --grub)"
    fi
}

stage_dms() {
    step "плагины и тема DMS"
    if [ -f "$TARGET_HOME/.config/dms/plugins.lock.json" ] && command -v dms >/dev/null 2>&1; then
        run dms plugins restore || warn "dms plugins restore не удался (нужен интернет и git)"
    fi
    if [ -x "$TARGET_HOME/.local/bin/theme-sync" ] && command -v dconf >/dev/null 2>&1; then
        run "$TARGET_HOME/.local/bin/theme-sync" dark || warn "theme-sync не сработал"
    fi
}

stage_verify() {
    step "проверка"
    "$ROOT/verify.sh" --config "$CONFIG" || warn "проверка нашла расхождения (см. выше)"
}

{
    printf 'TARGET_USER=%s\nTARGET_HOME=%s\nHOSTNAME=%s\nTIMEZONE=%s\nGREETER=%s\n' \
        "$TARGET_USER" "$TARGET_HOME" "$HOSTNAME" "$TIMEZONE" "$GREETER"
    printf 'PACKAGES="%s"\n' "$PACKAGES"
    printf 'STAMP=%s\n' "$STAMP"
} > "$STATE_OUT"

printf '== %s ==\n' "$MSG_TITLE"
log "конфигурация: $CONFIG"
log "пользователь: $TARGET_USER ($TARGET_HOME), машина: $HOSTNAME, вход: $GREETER"
[ "$DRY" = 1 ] && warn "режим --dry-run: система не изменяется"

group_state_on() { printf '%s' "$(eval "echo \${GROUP_$1:-off}")"; }

run_stage() {
    case $1 in
        repos) stage_repos ;;
        packages) stage_packages ;;
        system) stage_system ;;
        services) stage_services ;;
        home) stage_home ;;
        assets) stage_assets ;;
        session) stage_session ;;
        grub) stage_grub ;;
        dms) stage_dms ;;
        verify) stage_verify ;;
        *) die "неизвестный этап: $1" ;;
    esac
}

ALL="repos packages system services home assets session grub dms verify"

# Без --yes подтверждение обязательно: если stdin не отвечает (пайп, CI),
# установка отменяется, а не применяется молча.
if [ "$ONLY" = all ] && [ "$DRY" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
    printf 'Применить изменения к системе? [y/N] '
    answer=
    read -r answer || answer=
    case $answer in
        [yYдД]*) : ;;
        *) log 'отменено (нет подтверждения; для автоматического прогона добавь --yes)'; exit 0 ;;
    esac
fi
case $ONLY in
    all) for stage in $ALL; do run_stage "$stage"; done ;;
    *) run_stage "$ONLY" ;;
    esac

printf '\n'
ok "готово. перезагрузись, чтобы проверить сессию"
printf '  проверка состояния: %s healthcheck%s\n' "$C_DIM" "$C_OFF"
printf '  журнал: %s\n' "$LOG"
