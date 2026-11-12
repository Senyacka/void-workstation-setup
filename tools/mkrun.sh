#!/bin/sh
# mkrun.sh - pack the repository into a single self-extracting file.
#
# tar and gzip are part of base-system on Void, so the archive is readable on
# a freshly installed machine with no extra packages.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-$ROOT/void-workstation.run}

if ! "$ROOT/tools/privacy-scan.sh" --quiet; then
    echo 'mkrun: репозиторий содержит персональные данные, сборка остановлена' >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Тот же список файлов, что и для флешки: только то, что нужно установщику.
list=$tmp/files.txt
"$ROOT/tools/runtime-files.sh" > "$list"
( cd "$ROOT" && tar -czf "$tmp/payload.tar.gz" -T "$list" )

# The offset is written as a 20-digit number, so substituting it cannot change
# the size of the header that ends up in front of the payload.
{
    printf '#!/bin/sh\n'
    printf '# Self-extracting setup: sh void-workstation.run [install.sh options]\n'
    printf 'set -eu\n'
    printf 'offset=00000000000000000000\n'
    printf 'dest=${XDG_CACHE_HOME:-$HOME/.cache}/void-workstation\n'
    printf 'mkdir -p "$dest"\n'
    printf 'tail -c +"$offset" "$0" | tar -xzf - -C "$dest"\n'
    printf 'cd "$dest" && exec sh ./install.sh "$@"\n'
} > "$tmp/head.sh"

head_size=$(wc -c < "$tmp/head.sh")
sed -i "s/^offset=00000000000000000000$/offset=$(printf '%020d' $((head_size + 1)))/" "$tmp/head.sh"
[ "$(wc -c < "$tmp/head.sh")" = "$head_size" ] || { echo 'mkrun: размер заголовка изменился' >&2; exit 1; }

cat "$tmp/head.sh" "$tmp/payload.tar.gz" > "$out"
chmod +x "$out"
printf 'готово: %s (%s)\n' "$out" "$(du -h "$out" | cut -f1)"
