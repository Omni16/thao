# Attribution — pack/devices + pack/flash

- `devices/*` (74 codenames, mỗi máy `super` + `parts_info` JSON):
  verbatim từ `SuperConfig/` của ToolBuildURCN
  (`https://github.com/lucnguyen06/ToolBuildURCN`). `pack.sh` đọc
  `super.size` thật của từng máy — không dùng default 9126805504,
  không hardcode danh sách partition (sửa 2 lỗi `packROM.sh`).
- `flash/com`, `flash/Data` (update-binary shell + flash data),
  `flash/Linux_FastbootInstall.sh`, `flash/Windows_FastbootInstall.bat`:
  verbatim từ `Omni16/nothingsvn_xiaomi-toolbuild`
  `bin/script2flash/`. Binaries (`fastboot*`, `zstd*`, `7zz`,
  `busybox`, `HMATools/`) KHÔNG copy — lấy từ repo Nothing hoặc
  package manager khi đóng zip.
- Công thức `lpmake` VAB/A-only học từ `packROM.sh` cùng repo.

`pack.sh` là code của repo này.
