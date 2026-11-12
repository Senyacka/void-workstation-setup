#!/bin/sh
# Hardware capability detection shared by the installer.
#
# Every function prints a path or a value and never fails: the caller decides
# what to do when nothing is found. SYSROOT makes the module testable against a
# fixture tree (used by `make check`).

: "${ROOT:?ROOT must be set}"

syspath()  { printf '%s/sys/%s'  "${SYSROOT:-}" "$1"; }
procpath() { printf '%s/proc/%s' "${SYSROOT:-}" "$1"; }
_read()    { cat "$1" 2>/dev/null || true; }

hw_cpu_vendor() {
    case $(_read "$(procpath cpuinfo)") in
        *GenuineIntel*) echo intel ;;
        *AuthenticAMD*) echo amd ;;
        *) echo unknown ;;
    esac
}

hw_cpu_model() {
    sed -n 's/^model name[[:space:]]*: //p' "$(procpath cpuinfo)" 2>/dev/null | head -1
}

hw_dmi()  { _read "$(syspath "class/dmi/id/$1")" | sed 's/[[:space:]]*$//' ; }
hw_model()  { hw_dmi product_name ; }
hw_vendor() { hw_dmi sys_vendor ; }

hw_gpu_devices() {
    for dev in "$(syspath bus/pci/devices)"/*; do
        [ -r "$dev/vendor" ] || continue
        case $(_read "$dev/class") in
            0x0300*|0x0302*|0x0380*) printf '%s\n' "$dev" ;;
        esac
    done
}

hw_gpu_vendors() {
    hw_gpu_devices | while IFS= read -r dev; do
        case $(_read "$dev/vendor") in
            0x8086) echo intel ;;
            0x1002) echo amd ;;
            0x10de) echo nvidia ;;
        esac
    done | sort -u
}

hw_gpu_ids() {
    hw_gpu_devices | while IFS= read -r dev; do
        printf '%s:%s\n' "$(_read "$dev/vendor" | sed 's/^0x//')" "$(_read "$dev/device" | sed 's/^0x//')"
    done | sort -u
}

hw_battery() {
    for bat in "$(syspath class/power_supply)"/*; do
        [ -d "$bat" ] || continue
        [ "$(_read "$bat/type")" = Battery ] || continue
        basename "$bat"
        return 0
    done
    return 0
}

hw_ac() {
    for ac in "$(syspath class/power_supply)"/*; do
        [ -d "$ac" ] || continue
        case $(_read "$ac/type") in
            Mains|USB) basename "$ac" ;;
        esac
    done
}

hw_charge_limit_path() {
    bat=$(hw_battery)
    [ -n "$bat" ] || return 0
    for attr in charge_control_end_threshold charge_stop_threshold; do
        if [ -e "$(syspath "class/power_supply/$bat/$attr")" ]; then
            printf '%s\n' "$attr"; return 0
        fi
    done
    return 0
}

hw_backlight() {
    for bl in "$(syspath class/backlight)"/*; do
        [ -d "$bl" ] || continue
        basename "$bl"
        return 0
    done
    return 0
}

hw_backlight_path() {
    bl=$(hw_backlight)
    [ -n "$bl" ] && printf '%s\n' "$(syspath "class/backlight/$bl/brightness")"
}

hw_rapl_path() {
    [ -e "$(syspath class/powercap/intel-rapl:0/constraint_0_power_limit_uw)" ] && \
        printf '%s\n' "$(syspath class/powercap/intel-rapl:0)"
}

hw_turbo_path() {
    [ -e "$(syspath devices/system/cpu/intel_pstate/no_turbo)" ] && \
        printf '%s\n' "$(syspath devices/system/cpu/intel_pstate/no_turbo)"
}

# Вентилятор ищется по стандартному hwmon, а не по модели ноутбука: в списке
# перечислены драйверы разных вендоров, у которых есть fan1_input. Если ни один
# не совпал, берётся любой hwmon с датчиком оборотов, иначе возвращается пусто.
hw_fan_hwmon() {
    preferred=; fallback=
    for dev in "$(syspath class/hwmon)"/*; do
        [ -r "$dev/fan1_input" ] || continue
        case $(_read "$dev/name") in
            asus|asus_wmi|asus-nb-wmi|thinkpad|dell_smm|hp|acer-wmi|msi-ec|nct*|it87*)
                [ -n "$preferred" ] || preferred=$(basename "$dev") ;;
            *) [ -n "$fallback" ] || fallback=$(basename "$dev") ;;
        esac
    done
    if [ -n "$preferred" ]; then printf '%s\n' "$preferred"
    elif [ -n "$fallback" ]; then printf '%s\n' "$fallback"
    fi
    return 0
}

hw_platform_profile_path() {
    [ -e "$(syspath firmware/acpi/platform_profile)" ] && \
        printf '%s\n' "$(syspath firmware/acpi/platform_profile)"
}

hw_is_vm() {
    case "$(hw_model)" in
        *VirtualBox*|*VMware*|*QEMU*|*KVM*|*Bochs*|*Parallels*) echo yes; return 0 ;;
    esac
    grep -qiE '^flags.*hypervisor' "$(procpath cpuinfo)" 2>/dev/null && { echo yes; return 0; }
    echo no
}

hw_external_outputs() {
    found=
    for conn in "$(syspath class/drm)"/*/status; do
        [ -r "$conn" ] || continue
        name=$(basename "$(dirname "$conn")")
        case $name in card*-* ) name=${name#card*-} ;; * ) continue ;; esac
        case $name in eDP-*|LVDS-*|DSI-*) continue ;; esac
        [ "$(_read "$conn")" = connected ] || continue
        found="$found $name"
    done
    printf '%s\n' "${found# }"
}
