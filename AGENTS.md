# AGENTS.md — thao

Bash pipeline: tải ROM MIUI/HyperOS → nhận diện → unpack → port (patch vendor) → pack (repack + zip flash). Git repo `Omni16/thao` (main); CI chạy `bash test.sh` (60 asserts, không cần root/quyền mạng); workflow `getrom` (dispatch + URL + `release_tag` optional) tải ROM trên runner, up ROM lên Release khi có tag.

## Structure

- `fuji` — dispatcher: `fuji {getRom|detect|unpack|port|pack} [opts]`
- `getRom` — entrypoint đơn giản kiểu Nothing/UR/MIO: `./getRom <link|file> [...]` (không flag; ra `downloads/FUJI-DL-*/`).
- `lib/common.sh` — log, `require_tool`, `check_url` (scheme allowlist + chặn host private/loopback). Mọi script source file này; mọi URL/input user phải đi qua `check_url`, luôn quote, không `eval`.
- `getrom/` — `getrom.sh` (manager: detect input → resolve → backend → verify → `getrom.json` + `rom-info.json` + `job.json` bàn giao cho detect), `resolve_rom.sh` (tên file → device/os/variant/region, offline; đã fix 3 lỗi getROM.sh: TW/TR check sau Global, xiaomi.eu tráo field, match lowercase `tw_global`), `resolver.sh` (local/magnet/torrent/github/gitlab/gdrive/mifirm/xiaomi/direct/ftp), `backends.sh` (aria2 `-c` resume + timeout > curl > wget; rclone cho gdrive), `verify.sh` (size/`--min-bytes`/sha256/file-magic, từ chối trang HTML).
- `detect/detect.sh` — 3 tầng: filename → archive (`unzip -l`: payload.bin/super/dat.br/META-INF) → props (`--deep` mới bung build.prop). Xuất `report.json` theo schema §84 của `docs/2.nhan-dien-rom.md` + key additive `super_detail` (best-effort từ `getsuper`, không bao giờ fail run).
- `unpack/unpack.sh` — `--type auto` (chạy detect) hoặc ép kiểu; payload ưu tiên MIO `payload_extract` (cần pip deps) rồi mới `payload-dumper-go`/`payload-extract`; dat.br dùng `brotli` (vendored x86_64 nếu có) + `sdat2img.py` ngoài; super merge bằng `simg2img` (vendored x86_64 nếu có) rồi tách bằng `shim_lpunpack.py` (stdlib-only, ưu tiên) / `lpunpack` — thiếu tool thì báo tên tool, không traceback.
- `third_party/mio/` — backend unpack từ MIO-KITCHEN-SOURCE (ColdWindScholar, lấy từ `/storage/emulated/0/SOUCRE_MIO_2.7z`, KHÔNG copy file 7z vào repo): `mio_core/*.py` verbatim (AGPL-3.0, giữ nguyên header), `shim_lpunpack.py` là code của repo, `bins/Linux/x86_64/` binary static (chỉ chạy trên x86_64/CI, `unpack.sh` gate bằng `uname -m`), `requirements-mio.txt` (zstandard, protobuf, requests — CI cài). Chi tiết + license: `third_party/mio/{README,ATTRIBUTION}.md`. Không sửa file verbatim; không vendor thêm binary arch khác khi chưa cần.
- `.github/workflows/ci.yml` — ubuntu-latest + python 3.12 + pip requirements-mio + `bash test.sh`.
- `port/` — patch vendor theo `report.json` (device/os/region/android): `port.sh` chạy `steps/` theo số (`00-extract` img→dirs bằng extract.erofs/MIO imgextractor; `10-avb` strip fstab mọi máy + patch flag vbmeta, KHÔNG allowlist; `20-props` spoof verifiedbootstate + vendor tweaks động; `30-mods` dispatch `mods/<OS>/*.sh` + `mods/universal/*.sh`; `40-selinux` chạy `tools/fix_selinux.py`) → `port.json`. `tools/` + logic sed copy từ `Omni16/nothingsvn_xiaomi-toolbuild` (xem `port/ATTRIBUTION.md`); `mods/` hiện trống, chép `.sh` từ `bin/modfile/` repo Nothing theo `port/mods/README.md`, không hardcode codename, không vendor APK.
- `pack/` — `pack.sh --parts parts/ --device <máy> [--os] [-o dist/] [--dry-run]`: đọc size/slots/parts thật từ `devices/<máy>/{super,parts_info}` (UR `SuperConfig` 74 máy, verbatim); build img (`mkfs.erofs`/`make_ext4fs` + fs_config/contexts); `lpmake` VAB/A-only full list (không default 9126805504, không hardcode 6 part); đóng zip với `flash/` skeleton (update-binary shell + fastboot scripts, KHÔNG binaries) → `pack.json`. Chi tiết nguồn: `pack/ATTRIBUTION.md`.
- Chuỗi job: `getRom` → `downloads/FUJI-DL-*/` (rom + `job.json` next=detect) → `detect --output` → `report.json` → `unpack -d` → `images/` → `port --report --images` → `parts/` + `port.json` → `pack --parts --device` → `dist/`.
- `docs/1.download.md`, `docs/2.nhan-dien-rom.md` — design docs (copy verbatim từ `/storage/emulated/0/Download/`; không sửa nội dung kỹ thuật khi chưa có lý do).
- `.opencode/opencode.json` is minimal (`{"$schema": ...}`) — no custom agents, permissions, or `instructions` entries. Add repo instructions here, not in another file, unless wiring via `opencode.json` `instructions`.
- `.opencode/package.json` pins `@opencode-ai/plugin@1.18.30`; deps already installed in `.opencode/node_modules/` (`plugin`, `sdk`). Reinstall with `npm install` run with workdir `.opencode/` (lockfile is `package-lock.json`, i.e. npm — not bun).
- `.opencode/.gitignore` ignores `node_modules`, `package.json`, `package-lock.json`, `bun.lock`, `.gitignore` — do not force-add them.

## Gotchas

- Neighbor dirs (`/root/fujibot`, `/root/FujiOS`, `/root/luon`, `/root/botbuild`, `/root/tools`) are **outside** this repo. Never reference or edit them as part of this project; home-level `/root/AGENTS.md` documents those projects and does not apply here.
- No skills under `.opencode/skills/` — none auto-load for this repo.
- Shell is non-interactive (no TTY): never use editors/pagers (`vim`, `less`) or interactive flags (`git add -p`, `bash -i`); prefer `git --no-pager` and tool flags like `-y`/`--no-edit`.
