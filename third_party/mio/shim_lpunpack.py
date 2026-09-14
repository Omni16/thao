#!/usr/bin/env python3
"""shim_lpunpack.py — CLI wrapper (repo's own code) around vendored MIO lpunpack.

Stdlib-only: works offline on any host with python3.8+.
Usage: shim_lpunpack.py <super.img> <outdir> [part ...]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "mio_core"))

from lpunpack import get_parts, unpack  # noqa: E402  (vendored, AGPL-3.0, see ../ATTRIBUTION.md)


def main(argv):
    if len(argv) < 3 or argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: shim_lpunpack.py <super.img> <outdir> [part ...]\n")
        return 1
    img, out, parts = argv[1], argv[2], argv[3:] or None
    if not os.path.isfile(img):
        sys.stderr.write(f"error: not found: {img}\n")
        return 1
    os.makedirs(out, exist_ok=True)
    try:
        names = get_parts(img)
    except Exception as e:  # noqa: BLE001 — report tool error, no traceback
        sys.stderr.write(f"error: cannot read super image: {e}\n")
        return 1
    if parts:
        unknown = [p for p in parts if p not in names]
        if unknown:
            sys.stderr.write(f"error: unknown partitions {unknown} (have: {' '.join(names)})\n")
            return 1
    unpack(img, out, parts)
    print("extracted: " + " ".join(parts or names))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
