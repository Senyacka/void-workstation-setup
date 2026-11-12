#!/bin/sh
# make-usb.sh <mountpoint> - положить на флешку только то, что нужно установщику.
#
# Копируется не «весь репозиторий минус мусор», а точный список файлов
# (tools/runtime-files.sh): ни git-истории, ни инструментов разработки, ни
# снимков этой машины на флешку не попадает.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRY=0
WITH_ASSETS=1
FORCE=0
DEST=

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) DRY=1 ;;
        --no-assets) WITH_ASSETS=0 ;;
        --force) FORCE=1 ;;
        -h|--help)
            cat <<'USAGE'
usage: make-usb.sh <mountpoint> [--dry-run] [--no-assets] [--force]
  --dry-run    показать, что будет скопировано, и выйти
  --no-assets  не копировать видео заставки (экономит 16 МБ)
  --force      перезаписать уже существующий каталог void-workstation
USAGE
            exit 0 ;;
        -*) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
        *) DEST=$1 ;;
    esac
    shift
done

[ -n "$DEST" ] || { echo 'usage: make-usb.sh /mnt/usb' >&2; exit 2; }
[ -d "$DEST" ] || { echo "нет каталога $DEST" >&2; exit 2; }

TARGET=$DEST/void-workstation
list=$(mktemp)
trap 'rm -f "$list" "$list.tmp"' EXIT

"$ROOT/tools/runtime-files.sh" > "$list"
if [ "$WITH_ASSETS" = 0 ]; then
    grep -v '^assets/' "$list" > "$list.tmp" || true
    mv "$list.tmp" "$list"
fi

count=$(wc -l < "$list")
bytes=$(while IFS= read -r file; do du -b "$ROOT/$file" 2>/dev/null || true; done < "$list" | awk '{ s += $1 } END { print s + 0 }')
human=$(awk -v b="$bytes" 'BEGIN { printf "%.1f МБ", b / 1048576 }')

if [ "$DRY" = 1 ]; then
    printf 'было бы скопировано файлов: %s (%s) в %s\n\n' "$count" "$human" "$TARGET"
    cat "$list"
    exit 0
fi

if [ -e "$TARGET" ] && [ "$FORCE" = 0 ]; then
    echo "$TARGET уже существует: удали её или добавь --force" >&2
    exit 2
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
( cd "$ROOT" && tar -cf - -T "$list" ) | ( cd "$TARGET" && tar -xf - )
cp "$ROOT/docs/USB-README.txt" "$TARGET/README.txt"

( cd "$TARGET" && find . -type f ! -name checksums.sha256 -print0 | sort -z \
    | xargs -0 sha256sum > checksums.sha256 )

# Проверки: синтаксис, работоспособность детекта, отсутствие личных данных.
fail=0
for script in "$TARGET"/*.sh "$TARGET"/lib/*.sh "$TARGET"/lang/*.sh; do
    sh -n "$script" || { echo "синтаксис: $script" >&2; fail=1; }
done
"$TARGET/detect.sh" >/dev/null || { echo 'detect.sh не запускается' >&2; fail=1; }
sh "$TARGET/install.sh" --help >/dev/null || { echo 'install.sh не запускается' >&2; fail=1; }
"$ROOT/tools/privacy-scan.sh" "$TARGET" >/dev/null || { echo 'в файлах на флешке есть личные данные' >&2; fail=1; }
for junk in tools collect.sh Makefile privacy packages/installed.tsv .git; do
    [ -e "$TARGET/$junk" ] && { echo "лишнее на флешке: $junk" >&2; fail=1; }
done
[ "$fail" = 0 ] || { echo 'сборка флешки не прошла проверки' >&2; exit 1; }

printf 'готово: %s\n' "$TARGET"
printf '  файлов: %s, размер: %s\n' "$count" "$(du -sh "$TARGET" | cut -f1)"
printf '  на целевой машине:\n'
printf '    sudo mount /dev/sdX1 /mnt/usb\n'
printf '    sh /mnt/usb/void-workstation/install.sh\n'
