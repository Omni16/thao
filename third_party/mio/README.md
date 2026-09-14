# third_party/mio — unpack backends from MIO-KITCHEN (see ATTRIBUTION.md)

## No-pip parts (stdlib-only, work offline + in `test.sh`)

- `mio_core/getsuper.py <ota.zip|payload.bin|URL>` → prints bash vars
  `super_group`, `super_size`, `super_list` (reads the payload manifest;
  for URLs it uses HTTP Range, no full download).
- `shim_lpunpack.py <super.img> <outdir> [parts...]` → splits super
  (used by `unpack.sh` before system `lpunpack`).

## Pip parts (GitHub Actions: `pip install -r requirements-mio.txt`)

- `python3 -m mio_core.payload_extract -t zip|bin|url -i IN -o OUT
  [-X boot,system] [-T N]` → extracts `payload.bin` (needs `zstandard`,
  `protobuf`, `requests`).
- `mio_core.imgextractor` / `ext4` → ext4 unpack in pure Python.

## x86_64 bins (`bins/Linux/x86_64/`, CI only)

`brotli` (.dat.br), `simg2img` (sparse merge), `extract.erofs` (erofs
partitions), `magiskboot` (boot), `lpmake` (repack later).
