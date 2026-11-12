#!/bin/sh
# Every package in packages/*.txt must have a short and a long description.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESC=$ROOT/packages/desc.tsv
[ -r "$DESC" ] || { echo 'check-desc: нет packages/desc.tsv' >&2; exit 1; }

missing=0
total=0
for file in "$ROOT"/packages/core.txt "$ROOT"/packages/hardware-*.txt "$ROOT"/packages/optional/*.txt; do
    [ -f "$file" ] || continue
    while IFS= read -r line; do
        pkg=$(printf '%s' "$line" | sed 's/#.*//' | tr -d ' \t')
        [ -n "$pkg" ] || continue
        total=$((total + 1))
        row=$(awk -F'\t' -v p="$pkg" '$1 == p { print; exit }' "$DESC")
        if [ -z "$row" ]; then
            printf '  нет описания: %s\n' "$pkg" >&2
            missing=$((missing + 1))
            continue
        fi
        fields=$(printf '%s' "$row" | awk -F'\t' '{ print NF }')
        if [ "$fields" -lt 4 ]; then
            printf '  неполное описание (нужно 4 колонки): %s\n' "$pkg" >&2
            missing=$((missing + 1))
        fi
    done < "$file"
done

if [ "$missing" -gt 0 ]; then
    printf 'check-desc: %s проблем из %s пакетов\n' "$missing" "$total" >&2
    exit 1
fi
printf 'check-desc: у всех %s пакетов есть описание\n' "$total"
