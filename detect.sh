#!/bin/sh
# detect.sh - report what this machine can use. Read-only.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR" && pwd)
. "$ROOT/lib/common.sh"
. "$ROOT/lib/hwdetect.sh"

MODE=${1:-report}

cpu=$(hw_cpu_vendor)
gpus=$(hw_gpu_vendors | tr '\n' ' ' | sed 's/ $//')
ids=$(hw_gpu_ids | tr '\n' ' ' | sed 's/ $//')
bat=$(hw_battery)
ac=$(hw_ac | tr '\n' ' ' | sed 's/ $//')
limit=$(hw_charge_limit_path)
rapl=$(hw_rapl_path)
turbo=$(hw_turbo_path)
fan=$(hw_fan_hwmon)
profile=$(hw_platform_profile_path)
backlight=$(hw_backlight)
vm=$(hw_is_vm)
extra=$(hw_external_outputs)

cap_ucode=no; cap_gpu=no; cap_power=no; cap_charge=no; cap_fan=no; cap_vm=$vm
case $cpu in intel|amd) cap_ucode=yes ;; esac
case " $gpus " in *" intel "*|*" amd "*|*" nvidia "*) cap_gpu=yes ;; esac
[ -n "$profile" ] && [ -n "$backlight" ] && cap_power=yes
[ -n "$limit" ] && cap_charge=yes
[ -n "$fan" ] && cap_fan=yes

if [ "$MODE" = export ]; then
    cat <<EOF
HW_CPU='$cpu'
HW_CPU_MODEL='$(hw_cpu_model)'
HW_VENDOR='$(hw_vendor)'
HW_MODEL='$(hw_model)'
HW_GPUS='$gpus'
HW_GPU_IDS='$ids'
HW_BATTERY='$bat'
HW_AC='$ac'
HW_LIMIT_ATTR='$limit'
HW_RAPL='$rapl'
HW_TURBO='$turbo'
HW_FAN_HWMON='$fan'
HW_PROFILE='$profile'
HW_BACKLIGHT='$backlight'
HW_VM='$vm'
HW_EXTERNAL='$extra'
CAP_UCODE='$cap_ucode'
CAP_GPU='$cap_gpu'
CAP_POWER='$cap_power'
CAP_CHARGE='$cap_charge'
CAP_FAN='$cap_fan'
EOF
    exit 0
fi

printf 'машина:      %s %s\n' "$(hw_vendor)" "$(hw_model)"
printf 'процессор:   %s (%s)\n' "$cpu" "$(hw_cpu_model)"
printf 'видео:       %s [%s]\n' "${gpus:-нет}" "${ids:-нет id}"
printf 'батарея:     %s · источники: %s\n' "${bat:-нет}" "${ac:-нет}"
printf 'лимит заряда:%s\n' "${limit:+ есть ($limit)}"
printf 'питание:     rapl=%s turbo=%s profile=%s\n' "${rapl:+да}" "${turbo:+да}" "${profile:+да}"
printf 'охлаждение:  вентилятор=%s подсветка=%s\n' "${fan:-нет}" "${backlight:-нет}"
printf 'виртуалка:   %s\n' "$vm"
printf 'внешние:     %s\n' "${extra:-нет подключённых}"
printf 'возможности: ucode=%s gpu=%s power=%s charge=%s fan=%s\n' \
    "$cap_ucode" "$cap_gpu" "$cap_power" "$cap_charge" "$cap_fan"
