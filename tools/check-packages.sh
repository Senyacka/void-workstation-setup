#!/bin/sh
# Fail if a package named in packages/*.txt does not exist in the repositories.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
missing=0
total=0

# One repository listing (all repos) is far faster than a query per name.
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
xbps-query -Rs '*' 2>/dev/null > "$listing" || true

for file in "$ROOT"/packages/core.txt "$ROOT"/packages/hardware-*.txt "$ROOT"/packages/optional/*.txt; do
    [ -f "$file" ] || continue
    while IFS= read -r line; do
        pkg=$(printf '%s' "$line" | sed 's/#.*//' | tr -d ' \t')
        [ -n "$pkg" ] || continue
        total=$((total + 1))
        if grep -qE "^\[[*i-]\] $pkg-[0-9]" "$listing"; then
            continue
        fi
        printf '  нет в репозиториях: %-24s (%s)\n' "$pkg" "${file#$ROOT/}" >&2
        missing=$((missing + 1))
    done < "$file"
done

if [ "$missing" -gt 0 ]; then
    printf 'check-packages: %s из %s имён не найдены\n' "$missing" "$total" >&2
    exit 1
fi
printf 'check-packages: все %s имён найдены в репозиториях\n' "$total"
