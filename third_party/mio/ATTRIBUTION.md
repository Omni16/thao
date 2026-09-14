# Attribution — third_party/mio

Unpack engines vendored verbatim from **MIO-KITCHEN-SOURCE**
by ColdWindScholar (<https://github.com/ColdWindScholar/MIO-KITCHEN-SOURCE>),
from local archive `/storage/emulated/0/SOUCRE_MIO_2.7z` (not in this repo).

## Python modules (`mio_core/`, verbatim, headers intact)

`getsuper.py`, `lpunpack.py`, `imgextractor.py`, `ext4.py`, `posix.py`,
`utils.py`, `blockimgdiff.py`, `rangelib.py`, `sparse_img.py`,
`update_metadata_pb2.py`, `payload_extract.py`

Licensed under the **GNU Affero General Public License v3.0** (per file
headers). They are used here as an external unpack backend; this repo's own
scripts (`fuji`, `download/`, `detect/`, `unpack/`, `shim_*.py`) are separate
works that only invoke them.

## Prebuilt binaries (`bins/Linux/x86_64/`, verbatim, x86_64 only)

| binary | upstream |
|---|---|
| `brotli` | google/brotli |
| `simg2img` | AOSP system/extras |
| `extract.erofs` | sekaiacg/erofs-utils |
| `magiskboot` | topjohnwu/Magisk |
| `lpmake` | AOSP system/extras (repack, future use) |

Each keeps its upstream license (see MIO `bin/licenses/`). They run on
**x86_64 Linux (GitHub Actions)** — not on aarch64 hosts; `unpack.sh`
only puts them on PATH when `uname -m` is `x86_64`.
