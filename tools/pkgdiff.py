#!/usr/bin/env python3
"""Compare installed package files with the checksums recorded by xbps.

xbps keeps a fingerprint of every file it installs in
/var/db/xbps/.<pkg>-files.plist. Hashing the files on disk against those
fingerprints yields the exact list of package-owned files that were modified
by hand -- the only /etc content worth carrying between machines.

No root required: the plists are world readable.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import sys

SECTIONS = ("conf_files", "files")


def file_sha256(path: str) -> str | None:
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


def fingerprint(path: str) -> tuple[int, int]:
    try:
        st = os.lstat(path)
    except OSError:
        return (-1, -1)
    return (st.st_mtime_ns, st.st_size)


def load_cache(path: str | None) -> dict:
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_cache(path: str | None, cache: dict) -> None:
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w") as handle:
            json.dump(cache, handle, indent=1, sort_keys=True)
    except OSError:
        pass


def read_plist(path: str) -> dict:
    import plistlib

    with open(path, "rb") as handle:
        return plistlib.load(handle)


def collect(db: str, cache: dict) -> dict:
    result = {
        "conf_modified": [],
        "files_modified": [],
        "missing": [],
        "unreadable": [],
        "packages": 0,
        "entries": 0,
        "hashed": 0,
    }

    for plist_path in sorted(glob.glob(os.path.join(db, ".*-files.plist"))):
        pkg = os.path.basename(plist_path)[1:-len("-files.plist")]
        result["packages"] += 1
        try:
            data = read_plist(plist_path)
        except Exception:  # noqa: BLE001 - a broken plist must not stop the scan
            continue

        for section in SECTIONS:
            for entry in data.get(section, []):
                path = entry.get("file")
                expected = entry.get("sha256")
                if not path or not expected:
                    continue
                result["entries"] += 1

                stamp = fingerprint(path)
                cached = cache.get(path)
                if cached and tuple(cached[:2]) == stamp:
                    actual = cached[2]
                else:
                    actual = file_sha256(path)
                    result["hashed"] += 1
                    if actual is not None:
                        cache[path] = [stamp[0], stamp[1], actual]

                if actual is None:
                    if not os.path.lexists(path):
                        result["missing"].append({"package": pkg, "file": path})
                    else:
                        result["unreadable"].append({"package": pkg, "file": path})
                elif actual != expected:
                    bucket = "conf_modified" if section == "conf_files" else "files_modified"
                    result[bucket].append({"package": pkg, "file": path})

    return result


def print_text(data: dict, only_conf: bool) -> None:
    print(f"packages: {data['packages']}, entries: {data['entries']}, hashed: {data['hashed']}")
    print(f"modified conf_files: {len(data['conf_modified'])}")
    for item in sorted(data["conf_modified"], key=lambda i: i["file"]):
        print(f"  {item['package']:28} {item['file']}")
    if not only_conf:
        print(f"modified files: {len(data['files_modified'])}")
        for item in sorted(data["files_modified"], key=lambda i: i["file"]):
            print(f"  {item['package']:28} {item['file']}")
    print(f"unreadable (no permission, not drift): {len(data.get('unreadable', []))}")
    print(f"missing: {len(data['missing'])}")
    for item in sorted(data["missing"], key=lambda i: i["file"]):
        print(f"  {item['package']:28} {item['file']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Find package files modified by hand")
    parser.add_argument("--db", default="/var/db/xbps", help="xbps database directory")
    parser.add_argument("--cache", default=None, help="cache file to speed up repeated runs")
    parser.add_argument("--json", action="store_true", help="print JSON (default: text)")
    parser.add_argument("--only-conf", action="store_true", help="report conf_files only")
    parser.add_argument("--tsv", action="store_true", help="machine readable: section<TAB>file<TAB>package")
    args = parser.parse_args(argv)

    cache = load_cache(args.cache)
    data = collect(args.db, cache)
    save_cache(args.cache, cache)

    if args.only_conf:
        data.pop("files_modified", None)

    if args.tsv:
        for section, key in (("conf", "conf_modified"), ("file", "files_modified")):
            if args.only_conf and section != "conf":
                continue
            for item in sorted(data.get(key, []), key=lambda i: i["file"]):
                print(f"{section}\t{item['file']}\t{item['package']}")
    elif args.json:
        json.dump(data, sys.stdout, indent=2, sort_keys=False)
        sys.stdout.write("\n")
    else:
        print_text(data, args.only_conf)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
