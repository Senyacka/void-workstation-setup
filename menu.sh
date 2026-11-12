#!/bin/sh
# menu.sh - interactive front-end of the setup. Writes state/menu.conf,
# which install.sh then applies. Never touches the system by itself.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR" && pwd)
. "$ROOT/lib/common.sh"
. "$ROOT/lib/hwdetect.sh"
. "$ROOT/ui.sh"

UI_LANG=${UI_LANG:-auto}
if [ "$UI_LANG" = auto ]; then
    if [ -n "$(locale charmap 2>/dev/null | grep -i utf)" ] && [ -t 1 ]; then UI_LANG=ru; else UI_LANG=en; fi
fi
[ -r "$ROOT/lang/$UI_LANG.sh" ] || UI_LANG=en
. "$ROOT/lang/$UI_LANG.sh"

# Состояние меню (логин, галочки) хранится ВНЕ репозитория: в каталоге
# пользователя, чтобы ни имя, ни выбор не попадали в набор настроек.
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/void-workstation
STATE=$STATE_DIR/menu.conf
mkdir -p "$STATE_DIR"

DESC=$ROOT/packages/desc.tsv
OPT_ORDER="cli-qol screenshots hardware-tools network backup media print-scan secrets dev vms docker apps x11-legacy"

ui_init

# --- description lookups -------------------------------------------------
pkg_short() { awk -F'\t' -v p="$1" '$1 == p { print $3; exit }' "$DESC"; }
pkg_long()  { awk -F'\t' -v p="$1" '$1 == p { print $4; exit }' "$DESC"; }

pkg_list() {
    file=$1
    [ -r "$file" ] || return 0
    sed 's/#.*//' "$file" | tr -d ' \t' | grep -v '^$'
}

group_file() {
    case $1 in
        base) printf '%s' "$ROOT/packages/core.txt" ;;
        hw-intel|hw-amd|hw-nvidia) printf '%s' "$ROOT/packages/hardware-${1#hw-}.txt" ;;
        *) printf '%s' "$ROOT/packages/optional/$1.txt" ;;
    esac
}

group_title() {
    case $1 in
        base) printf 'БАЗА (обязательно)' ;;
        hw-intel) printf 'ОБОРУДОВАНИЕ: Intel' ;;
        hw-amd) printf 'ОБОРУДОВАНИЕ: AMD' ;;
        hw-nvidia) printf 'ОБОРУДОВАНИЕ: NVIDIA' ;;
        cli-qol) printf 'CLI QoL' ;;
        screenshots) printf 'Скриншоты и запись' ;;
        hardware-tools) printf 'Железо и диагностика' ;;
        network) printf 'Сеть' ;;
        backup) printf 'Бэкап' ;;
        media) printf 'Медиа' ;;
        print-scan) printf 'Печать и сканирование' ;;
        secrets) printf 'Секреты и биометрия' ;;
        dev) printf 'Разработка' ;;
        vms) printf 'Виртуальные машины' ;;
        docker) printf 'Контейнеры Docker' ;;
        apps) printf 'Приложения' ;;
        x11-legacy) printf 'Наследство X11' ;;
    esac
}

group_order() {
    printf 'base'
    [ "$(hw_cpu_vendor)" = intel ] && printf ' hw-intel'
    case " $(hw_gpu_vendors | tr '\n' ' ') " in *" intel "*) printf ' hw-intel' ;; esac
    [ "$(hw_cpu_vendor)" = amd ] && printf ' hw-amd'
    case " $(hw_gpu_vendors | tr '\n' ' ') " in *" amd "*) printf ' hw-amd' ;; esac
    case " $(hw_gpu_vendors | tr '\n' ' ') " in *" nvidia "*) printf ' hw-nvidia' ;; esac
    printf ' %s' "$OPT_ORDER"
}

# --- state ---------------------------------------------------------------
flag_file=$STATE_DIR/flags
: >> "$flag_file"

flag_get() { grep -qx "$1" "$flag_file" && echo on || echo off; }
flag_set() {
    flag_del "$1"
    [ "$2" = on ] && printf '%s\n' "$1" >> "$flag_file"
    return 0
}
flag_del() { grep -vx "$1" "$flag_file" > "$flag_file.tmp" 2>/dev/null || true; mv "$flag_file.tmp" "$flag_file"; }

group_state() {
    group=$1; on=0; off=0
    for pkg in $(pkg_list "$(group_file "$group")"); do
        case $(flag_get "pkg:$pkg") in on) on=$((on+1)) ;; *) off=$((off+1)) ;; esac
    done
    if [ "$on" -gt 0 ] && [ "$off" -eq 0 ]; then echo on
    elif [ "$on" -eq 0 ]; then echo off
    else echo partial; fi
}

group_set() {
    group=$1; value=$2
    for pkg in $(pkg_list "$(group_file "$group")"); do
        flag_set "pkg:$pkg" "$value"
    done
}

group_count() { pkg_list "$(group_file "$1")" | wc -l; }

apply_preset() {
    preset=$1
    : > "$flag_file"
    if [ "$preset" = manual ]; then
        group_set base on
        for g in $(group_order); do case $g in base|hw-*) ;; *) group_set "$g" off ;; esac; done
        return 0
    fi
    while IFS='=' read -r key value; do
        key=$(printf '%s' "$key" | tr -d ' \t')
        value=$(printf '%s' "$value" | tr -d ' \t')
        [ -n "$key" ] || continue
        case $key in ''|'#'*) continue ;; esac
        case $value in auto) value=on ;; esac
        group_set "$key" "$value"
    done < "$preset"
    group_set base on
}

selected_count() {
    n=0
    for g in $(group_order); do
        for pkg in $(pkg_list "$(group_file "$g")"); do
            [ "$(flag_get "pkg:$pkg")" = on ] && n=$((n+1))
        done
    done
    echo "$n"
}

pkg_size_bytes() {
    pkg=$1
    cache=$STATE_DIR/sizes.tsv
    size=$(awk -F'\t' -v p="$pkg" '$1 == p { print $2; exit }' "$cache" 2>/dev/null || true)
    if [ -z "${size:-}" ]; then
        size=$(xbps-query -R -p filename-size "$pkg" 2>/dev/null || echo 0)
        printf '%s\t%s\n' "$pkg" "$size" >> "$cache"
    fi
    printf '%s' "$size"
}

total_size() {
    total=0
    for g in $(group_order); do
        for pkg in $(pkg_list "$(group_file "$g")"); do
            [ "$(flag_get "pkg:$pkg")" = on ] || continue
            size=$(pkg_size_bytes "$pkg")
            case $size in *KB) total=$((total + ${size%KB})) ;; esac
        done
    done
    printf '%s МБ' "$(( total / 1024 ))"
}

# --- screens -------------------------------------------------------------
screen_detect() {
    report=$STATE_DIR/detect.txt
    "$ROOT/detect.sh" > "$report"
    text=$(cat "$report")
    ui_yesno "$MSG_DETECT_TITLE" "$text

$MSG_DETECT_HELP"
}

screen_preset() {
    set --
    prev=
    for preset in "$ROOT"/presets/*.conf; do
        [ -f "$preset" ] || continue
        name=$(sed -n 's/^# name: //p' "$preset" | head -1)
        desc=$(sed -n 's/^# description: //p' "$preset" | head -1)
        [ -n "$name" ] || name=$(basename "$preset" .conf)
        set -- "$@" "$preset" "$name — $desc"
    done
    set -- "$@" manual "$MSG_PRESET_MANUAL — $MSG_PRESET_MANUAL_DESC"
    choice=$(ui_menu "$MSG_PRESET_TITLE" "$MSG_PRESET_HELP

$MSG_KEYS_MENU" "$@") || return 1
    apply_preset "$choice"
    printf 'PRESET=%s\n' "$choice" > "$STATE_DIR/preset"
    return 0
}

screen_hardware() {
    set --
    set -- "$@" hw_policy "Политика питания и вентиляторов" "$( [ "$CAP_POWER" = yes ] && echo on || echo off )" \
        "turbo/RAPL/ASPM/яркость/обдув: доступно=$CAP_POWER"
    set -- "$@" hw_charge "Лимит заряда батареи" "$( [ "$CAP_CHARGE" = yes ] && echo on || echo off )" \
        "udev + helper: доступно=$CAP_CHARGE"
    set -- "$@" hw_acpi "Обработчик ACPI (крышка, кнопки)" on "умная крышка и кнопки питания"
    if printf '%s' "$HW_GPUS" | grep -q nvidia; then
        set -- "$@" hw_gpu_dropin "Параметры ядра для GPU" on "nvidia-drm.modeset=1"
    elif printf '%s' "$HW_GPU_IDS" | grep -q '8086:7d51'; then
        set -- "$@" hw_gpu_dropin "Параметры ядра для GPU" on "xe.force_probe=!7d51 (только для этого GPU)"
    fi
    chosen=$(ui_checklist "$MSG_HW_TITLE" "$MSG_HW_HELP

$MSG_KEYS_LIST" "$@") || return 1
    for key in hw_policy hw_charge hw_acpi hw_gpu_dropin; do
        case " $chosen " in *" $key "*) flag_set "cap:$key" on ;; *) flag_set "cap:$key" off ;; esac
    done
    return 0
}

screen_packages() {
    before=$STATE_DIR/groupstate.before
    while :; do
        set --
        : > "$before"
        for g in $(group_order); do
            state=$(group_state "$g")
            printf '%s	%s
' "$g" "$state" >> "$before"
            status=off
            [ "$state" = off ] || status=on
            suffix=
            [ "$state" = partial ] && suffix=' (частично)'
            set -- "$@" "g:$g" "▉ $(group_title "$g") — $(group_count "$g")$suffix" "$status"                 "группа: пробел включает или выключает все пакеты"
            for pkg in $(pkg_list "$(group_file "$g")"); do
                set -- "$@" "p:$pkg" "    $pkg" "$(flag_get "pkg:$pkg")" "$(pkg_short "$pkg")"
            done
        done
        header=$(printf "$MSG_PKG_TOTAL" "$(selected_count)" "—" "—")
        chosen=$(ui_checklist "$MSG_PKG_TITLE" "$header
$MSG_PKG_HELP
$MSG_KEYS_LIST" "$@") || return 1

        bulk=
        for g in $(group_order); do
            case $g in base|hw-*) continue ;; esac
            was=$(awk -F'	' -v g="$g" '$1 == g { print $2; exit }' "$before")
            now=off
            printf '%s
' "$chosen" | grep -qx "g:$g" && now=on
            if [ "$was" = off ] && [ "$now" = on ]; then
                group_set "$g" on; bulk="$bulk $g"
            elif [ "$was" != off ] && [ "$now" = off ]; then
                group_set "$g" off; bulk="$bulk $g"
            fi
        done

        for g in $(group_order); do
            case " $bulk " in *" $g "*) continue ;; esac
            for pkg in $(pkg_list "$(group_file "$g")"); do
                case " $chosen " in
                    *" p:$pkg "*) flag_set "pkg:$pkg" on ;;
                    *) flag_set "pkg:$pkg" off ;;
                esac
            done
        done

        # base and the hardware support for THIS machine are mandatory
        group_set base on
        for g in $(group_order); do
            case $g in hw-*) group_set "$g" on ;; esac
        done

        [ -n "$bulk" ] || break
        summary "$bulk"
    done
    return 0
}

summary() {
    bulk=${1:-}
    text="$MSG_SUMMARY_TITLE"
    [ -n "$bulk" ] && text="$text
(изменены группы:$bulk)"
    text="$text
"
    for g in $(group_order); do
        text="$text
 $(group_title "$g"): $(group_state "$g") · $(group_count "$g") шт."
    done
    text="$text

$MSG_PKG_LOCKED

$(printf "$MSG_PKG_TOTAL" "$(selected_count)" "$(total_size)" "?")"
    ui_msgbox "$MSG_SUMMARY_TITLE" "$text"
}

screen_user() {
    answers=$(ui_form "$MSG_USER_TITLE" "$MSG_KEYS_FORM" \
        "$MSG_LOGIN" "$TARGET_USER" "$MSG_HOME" "$TARGET_HOME" "$MSG_HOST" "$HOSTNAME") || return 1
    i=1
    while IFS= read -r line; do
        case $i in
            1) TARGET_USER=$line ;;
            2) TARGET_HOME=$line ;;
            3) HOSTNAME=$line ;;
        esac
        i=$((i+1))
    done <<EOF
$answers
EOF
    tz=$(ui_menu "$MSG_TZ" "$MSG_KEYS_MENU" \
        UTC UTC Europe/Moscow "Europe/Moscow (UTC+3)" Europe/Berlin "Europe/Berlin" Asia/Yekaterinburg "Asia/Yekaterinburg" custom "ввести вручную") || return 1
    if [ "$tz" = custom ]; then
        tz=$(ui_form "$MSG_TZ" "$MSG_KEYS_FORM" "$MSG_TZ" "$TIMEZONE" | head -1) || return 1
    fi
    TIMEZONE=$tz
    return 0
}

screen_session() {
    choice=$(ui_menu "$MSG_SESSION_TITLE" "$MSG_KEYS_MENU" \
        dms "$MSG_SESSION_DMS" tuigreet "$MSG_SESSION_TUI") || return 1
    GREETER=$choice
    return 0
}

write_state() {
    {
        printf 'TARGET_USER=%s\n' "$TARGET_USER"
        printf 'TARGET_HOME=%s\n' "$TARGET_HOME"
        printf 'HOSTNAME=%s\n' "$HOSTNAME"
        printf 'TIMEZONE=%s\n' "$TIMEZONE"
        printf 'LOCALE=%s\n' "${LOCALE:-en_US.UTF-8}"
        printf 'GREETER=%s\n' "${GREETER:-dms}"
        printf 'PRESET=%s\n' "$(cat "$STATE_DIR/preset" 2>/dev/null || echo manual)"
        printf 'HW_CPU=%s\n' "${HW_CPU:-unknown}"
        printf 'HW_GPUS=%s\n' "${HW_GPUS:-}"
        printf 'HW_GPU_IDS=%s\n' "${HW_GPU_IDS:-}"
        printf 'HW_BATTERY=%s\n' "${HW_BATTERY:-}"
        for cap in hw_policy hw_charge hw_acpi hw_gpu_dropin; do
            printf 'CAP_%s=%s\n' "$(printf '%s' "$cap" | tr 'a-z-' 'A-Z_')" "$(flag_get "cap:$cap")"
        done
        for g in $(group_order); do
            printf 'GROUP_%s=%s\n' "$(printf '%s' "$g" | tr 'a-z-' 'A-Z_')" "$(group_state "$g")"
        done
        printf 'PACKAGES="'
        sep=
        for g in $(group_order); do
            for pkg in $(pkg_list "$(group_file "$g")"); do
                [ "$(flag_get "pkg:$pkg")" = on ] || continue
                printf '%s%s' "$sep" "$pkg"; sep=' '
            done
        done
        printf '"\n'
    } > "$STATE"
    log "состояние записано: $STATE"
}

# --- main ----------------------------------------------------------------
TARGET_USER=${TARGET_USER:-$(id -un)}
TARGET_HOME=${TARGET_HOME:-$HOME}
HOSTNAME=${HOSTNAME:-void}
TIMEZONE=${TIMEZONE:-UTC}
GREETER=${GREETER:-dms}
PRESET_FILE=

eval "$("$ROOT/detect.sh" export)"

screen_detect || { log "выход"; exit 0; }

presets_done=0
while :; do
    if [ "$presets_done" = 0 ]; then
        screen_preset || exit 0
        presets_done=1
    fi
    screen_hardware   || { presets_done=0; continue; }
    screen_packages   || { presets_done=0; continue; }
    screen_user       || continue
    screen_session    || continue
    break
done

write_state
mode=$(ui_menu "$MSG_MODE_TITLE" "$MSG_KEYS_MENU" \
    plan "$MSG_MODE_PLAN" install "$MSG_MODE_INSTALL" verify "$MSG_MODE_VERIFY" \
    collect "$MSG_MODE_COLLECT" save "$MSG_MODE_SAVE") || exit 0

case $mode in
    plan)    "$ROOT/install.sh" --config "$STATE" --dry-run ;;
    install) exec "$ROOT/install.sh" --config "$STATE" --yes ;;
    verify)  exec "$ROOT/install.sh" --config "$STATE" --only verify ;;
    collect) exec "$ROOT/collect.sh" ;;
    save)
        name=$(ui_form "$MSG_MODE_SAVE" "$MSG_KEYS_FORM" "Имя пресета" "my-preset" | head -1) || exit 0
        cp "$STATE" "$ROOT/presets/${name}.conf"
        log "пресет сохранён: $ROOT/presets/${name}.conf"
        ;;
esac
