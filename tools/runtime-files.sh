#!/bin/sh
# runtime-files.sh - what the installer actually needs on the target machine.
#
# Prints repository-relative paths, one per line. Everything that exists only
# for development (collect.sh, tools/, privacy/, Makefile, snapshots of this
# machine) is deliberately absent.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

{ 
    printf '%s\n' install.sh menu.sh ui.sh detect.sh verify.sh README.md install.conf.example
    printf '%s\n' docs/logo.svg
    printf '%s\n' lib/common.sh lib/hwdetect.sh
    printf '%s\n' lang/ru.sh lang/en.sh
    printf '%s\n' packages/core.txt packages/desc.tsv
    printf '%s\n' packages/hardware-intel.txt packages/hardware-amd.txt packages/hardware-nvidia.txt
    printf '%s\n' system/MANIFEST system/EXCLUDE.txt

    [ -d "$ROOT/packages/optional" ] && ( cd "$ROOT" && find packages/optional -type f | sort )
    [ -d "$ROOT/presets" ] && ( cd "$ROOT" && find presets -type f -name '*.conf' | sort )
    [ -d "$ROOT/system/root" ] && ( cd "$ROOT" && find system/root -type f | sort )
    [ -d "$ROOT/home" ] && ( cd "$ROOT" && find home -type f | sort )
    [ -d "$ROOT/assets" ] && ( cd "$ROOT" && find assets -type f | sort )
} | grep -v '^$'
