#!/usr/bin/env python3
"""Write a sanitized copy of one agent config file, or hash it.

Usage:
  sanitize.py <home_rel> <src> <dest>   write the sanitized copy
  sanitize.py --hash <home_rel> <src>   print sha256 of the sanitized bytes

Rules are keyed by the file's path relative to the home directory. A path
with no rule is copied byte for byte.
"""

import hashlib
import json
import sys
from pathlib import Path

# home_rel -> ((action, key), ...). Actions: "drop" deletes the key,
# "blank" sets it to "".
RULES = {
    ".pi/agent/settings.json": (
        ("drop", "lastChangelogVersion"),
        ("drop", "extensionChangelogVersions"),
    ),
    ".pi/agent/pi-ntfy.json": (("blank", "topic"),),
    ".config/openspec/config.json": (("drop", "telemetry.anonymousId"),),
}


def _docker(obj: dict, dotted: str):
    """Return the deepest dict along a dotted path, or None."""
    node = obj
    for part in dotted.split(".")[:-1]:
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node if isinstance(node, dict) else None


def sanitize(home_rel: str, data: bytes) -> bytes:
    actions = RULES.get(home_rel)
    if not actions:
        return data
    try:
        obj = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{home_rel}: invalid JSON: {exc}") from exc
    if not isinstance(obj, dict):
        return data
    for action, key in actions:
        parent = _docker(obj, key)
        if parent is None:
            continue
        leaf = key.split(".")[-1]
        if action == "drop":
            parent.pop(leaf, None)
        elif action == "blank":
            parent[leaf] = ""
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "--hash":
        home_rel, src = argv[2], argv[3]
        try:
            data = Path(src).read_bytes()
        except OSError as exc:
            print(f"sanitize: {exc}", file=sys.stderr)
            return 2
        try:
            print(hashlib.sha256(sanitize(home_rel, data)).hexdigest())
        except ValueError as exc:
            print(f"sanitize: {exc}", file=sys.stderr)
            return 2
        return 0

    if len(argv) == 4:
        home_rel, src, dest = argv[1], argv[2], argv[3]
        try:
            data = Path(src).read_bytes()
            Path(dest).parent.mkdir(parents=True, exist_ok=True)
            Path(dest).write_bytes(sanitize(home_rel, data))
        except (OSError, ValueError) as exc:
            print(f"sanitize: {exc}", file=sys.stderr)
            return 2
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
