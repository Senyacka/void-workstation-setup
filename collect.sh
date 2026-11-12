#!/bin/sh
# collect.sh - snapshot this machine into the repository.
#
# Only what differs from the packaged defaults is taken from /etc; the home
# directory is taken from an explicit whitelist. Personal identifiers are
# replaced with placeholders and privacy-scan.sh must pass before the snapshot
# is considered usable.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SELF_DIR" && pwd)
COLLECT_USER=${SUDO_USER:-$(id -un)}
export COLLECT_USER
. "$ROOT/lib/common.sh"

ONLY=all
DO_SCAN=1
while [ $# -gt 0 ]; do
    case $1 in
        --only) ONLY=${2:?--only needs a stage}; shift ;;
        --no-scan) DO_SCAN=0 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) die "неизвестный аргумент: $1" ;;
    esac
    shift
done

# --- what never travels -------------------------------------------------
MACHINE_FILES="
/etc/fstab
/etc/hostname
/etc/passwd
/etc/group
/etc/shadow
/etc/gshadow
/etc/subuid
/etc/subgid
/etc/adjtime
/etc/machine-id
/etc/ld.so.cache
/etc/mtab
/etc/resolv.conf
/etc/securetty
"

# Reproduced by installing the package that owns it - not a manual choice.
PKGDRIFT_FILES="
/etc/pam.d/login
"

# Files no package owns: they exist only because they were written by hand.
UNOWNED_FILES="
/usr/local/sbin/power-sync
/usr/local/sbin/battery-charge-limit
/etc/battery-charge-limit.conf
/etc/udev/rules.d/99-battery-charge-limit.rules
/etc/sudoers.d/wheel
/etc/xbps.d/danklinux.conf
/etc/xbps.d/dms.conf
/etc/xbps.d/sofijacom-void-repository.conf
"

HOME_FILES="
.bashrc
.bash_profile
.Xresources
.config/niri/config.kdl
.config/dms/settings.json
.config/dms/custom-theme.json
.config/dms/plugin_settings.json
.config/dms/plugins.lock.json
.config/dms/firefox.css
.config/kitty/kitty.conf
.config/kitty/dank-theme.conf
.config/kitty/dank-tabs.conf
.config/gtk-3.0/settings.ini
.config/gtk-3.0/gtk.css
.config/gtk-3.0/dank-colors.css
.config/gtk-4.0/gtk.css
.config/gtk-4.0/dank-colors.css
.config/fontconfig/fonts.conf
.config/environment.d/libreoffice.conf
.config/xdg-desktop-portal/portals.conf
.config/mimeapps.list
.local/bin/healthcheck
.local/bin/theme-sync
.local/bin/fanmode
.local/bin/power-log
.local/bin/power-ab
.local/bin/start-session-audio
.local/bin/thunar
"

HOME_DIRS="
.config/service
.config/sv
.local/share/themes/adw-gtk3
.local/share/themes/adw-gtk3-dark
.local/share/themes/adw-gtk3-glass
.local/share/color-schemes
.local/share/fonts
"

in_list() {
    for item in $2; do
        [ "$item" = "$1" ] && return 0
    done
    return 1
}

sanitize_tree() {
    find "$1" -type f -print | while IFS= read -r file; do
        case $file in *.mp4|*.ttf|*.otf|*.woff2|*.png|*.jpg) continue ;; esac
        sanitize_home_paths "$file"
    done
}

# --- stages -------------------------------------------------------------
collect_packages() {
    step "пакеты: снимок установленного"
    {
        xbps-query -m | while IFS= read -r pkgver; do
            printf '%s\t%s\n' "$(xbps-uhelper getpkgname "$pkgver")" "$pkgver"
        done
    } | sort > "$ROOT/packages/installed.tsv"
    log "записано $ROOT/packages/installed.tsv ($(wc -l < "$ROOT/packages/installed.tsv") пакетов)"

    curated=$(cat "$ROOT"/packages/core.txt "$ROOT"/packages/hardware-*.txt "$ROOT"/packages/optional/*.txt 2>/dev/null \
        | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$' | sort -u || true)
    [ -n "$curated" ] || return 0
    ignored=$(sed 's/#.*//' "$ROOT/packages/ignored.txt" 2>/dev/null | tr -s ' \t' '\n' | grep -v '^$' || true)
    mandatory=$(cat "$ROOT"/packages/core.txt "$ROOT"/packages/hardware-*.txt 2>/dev/null \
        | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$' | sort -u || true)

    tmp=$(mktemp -d)
    cut -f1 "$ROOT/packages/installed.tsv" | sort -u > "$tmp/installed"
    printf '%s\n' "$curated" | sort -u > "$tmp/curated"
    printf '%s\n' "$ignored" | sort -u > "$tmp/ignored"
    printf '%s\n' "$mandatory" | sort -u > "$tmp/mandatory"

    unclassified=$(comm -23 "$tmp/installed" "$tmp/curated" | comm -23 - "$tmp/ignored")
    absent=$(comm -23 "$tmp/mandatory" "$tmp/installed")
    rm -rf "$tmp"

    [ -n "$unclassified" ] && warn "установлены, но не отнесены ни к одной группе: $(printf '%s ' $unclassified)"
    [ -n "$absent" ] && warn "обязательные пакеты не установлены: $(printf '%s ' $absent)"
    return 0
}

collect_system() {
    step "система: только файлы, отличающиеся от пакетных дефолтов"
    work=$ROOT/.collect/system
    rm -rf "$work"; mkdir -p "$work"

    python3 "$ROOT/tools/pkgdiff.py" --tsv --only-conf --cache "${XDG_CACHE_HOME:-$HOME/.cache}/pkgdiff.json" > "$work/drift.tsv"

    : > "$work/MANIFEST"
    while IFS=$(printf '\t') read -r section path pkg; do
        [ -n "${path:-}" ] || continue
        if in_list "$path" "$MACHINE_FILES"; then
            printf 'machine identity, not collected: %s\n' "$path"
            continue
        fi

        kind=ours
        in_list "$path" "$PKGDRIFT_FILES" && kind=pkgdrift

        base=$(xbps-query -p pkgver "$pkg" 2>/dev/null || printf '%s' "$pkg")
        dst=$work/root$path
        mkdir -p "$(dirname "$dst")"
        cp -a "$path" "$dst"
        printf '%s\t%s\t%s\t%s\n' "$path" "$kind" "$base" "$(sha256sum "$dst" | cut -d' ' -f1)" >> "$work/MANIFEST"
    done < "$work/drift.tsv"

    for path in $UNOWNED_FILES; do
        if [ ! -e "$path" ]; then
            warn "нет $path - пропущено"
            continue
        fi
        dst=$work/root$path
        mkdir -p "$(dirname "$dst")"
        cp -a "$path" "$dst"
        printf '%s\t%s\t%s\t%s\n' "$path" unowned - "$(sha256sum "$dst" | cut -d' ' -f1)" >> "$work/MANIFEST"
    done

    sanitize_tree "$work/root"

    # checksums must describe the stored (sanitized) content
    : > "$work/MANIFEST.new"
    while IFS=$(printf '\t') read -r path kind base sha; do
        stored=$work/root$path
        [ -f "$stored" ] && sha=$(sha256sum "$stored" | cut -d' ' -f1)
        printf '%s\t%s\t%s\t%s\n' "$path" "$kind" "$base" "$sha" >> "$work/MANIFEST.new"
    done < "$work/MANIFEST"
    sort "$work/MANIFEST.new" > "$work/MANIFEST"; rm -f "$work/MANIFEST.new"

    rm -rf "$ROOT/system/root"
    mv "$work/root" "$ROOT/system/root"
    mv "$work/MANIFEST" "$ROOT/system/MANIFEST"
    rm -rf "$work"

    log "файлов в system/root: $(find "$ROOT/system/root" -type f | wc -l), строк в MANIFEST: $(wc -l < "$ROOT/system/MANIFEST")"
}

collect_home() {
    step "home: dotfiles по белому списку"
    work=$ROOT/.collect/home
    rm -rf "$work"; mkdir -p "$work"

    for rel in $HOME_FILES; do
        src=$HOME/$rel
        if [ ! -e "$src" ]; then
            warn "нет ~/$rel - пропущено"
            continue
        fi
        dst=$work/$rel
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    done

    for rel in $HOME_DIRS; do
        src=$HOME/$rel
        [ -d "$src" ] || { warn "нет ~/$rel - пропущено"; continue; }
        dst=$work/$rel
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    done

    find "$work" -type d -name supervise -prune -exec rm -rf {} + 2>/dev/null || true

    sanitize_tree "$work"
    strip_git_identity "$work/.gitconfig"
    drop_lines_matching "$work/.config/mimeapps.list" 'postman\.desktop'

    mkdir -p "$work/dconf"
    if command -v dconf >/dev/null 2>&1; then
        dconf dump / 2>/dev/null \
            | awk '/^\[/ { keep = ($0 !~ /mousepad|gedit|recently|history|xfce4\/file-manager/) } keep'
    else
        warn "dconf недоступен - workstation.ini не собран"
    fi > "$work/dconf/workstation.ini"
    sanitize_home_paths "$work/dconf/workstation.ini"

    rm -rf "$ROOT/home"
    mv "$work" "$ROOT/home"
    rm -rf "$ROOT/.collect"
    log "файлов в home/: $(find "$ROOT/home" -type f | wc -l)"
}

collect_assets() {
    step "assets: заставка локскрина"
    src=$HOME/Videos/lockscreen
    if [ -d "$src" ]; then
        mkdir -p "$ROOT/assets/lockscreen"
        found=0
        for file in "$src"/*.mp4; do
            [ -f "$file" ] || continue
            cp -a "$file" "$ROOT/assets/lockscreen/"
            found=$((found + 1))
        done
        log "скопировано видео: $found"
    else
        warn "нет ~/Videos/lockscreen - пропущено"
    fi
}

summary() {
    printf '\n'
    for dir in system home assets packages; do
        [ -e "$ROOT/$dir" ] && printf '  %-10s %s\n' "$dir" "$(du -sh "$ROOT/$dir" 2>/dev/null | cut -f1)"
    done
}

case $ONLY in
    all) collect_packages; collect_system; collect_home; collect_assets ;;
    packages) collect_packages ;;
    system) collect_system ;;
    home) collect_home ;;
    assets) collect_assets ;;
    *) die "--only: packages|system|home|assets|all" ;;
 esac

if [ "$DO_SCAN" = 1 ]; then
    step "проверка на персональные данные"
    if ! "$ROOT/tools/privacy-scan.sh"; then
        die "в репозиторий попали личные данные (см. выше) - исправь collect.sh или файлы"
    fi
fi

summary
