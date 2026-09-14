# Attribution — port/tools + port/steps logic

- `tools/fix_selinux.py`, `tools/patch-vbmeta.py`: verbatim từ
  `Omni16/nothingsvn_xiaomi-toolbuild` (`bin/fix_selinux.py`,
  `bin/patch-vbmeta.py`).
- `tools/koushi-build.prop`, `tools/koushi-cust.prop`: verbatim từ
  `bin/package/KouseiPatcher/prop/{build,cust}.prop` cùng repo.
- `steps/10-avb.sh`: dãy `sed` strip fstab copy từ `disable_avb_verify`
  trong `functions.sh` cùng repo — nhưng chạy cho **mọi máy** (bỏ
  `avb_list.txt` allowlist) và luôn patch flag vbmeta.
- `steps/30-mods.sh`: pattern dispatch `find + bash *.sh` theo OS học từ
  `bin/modfile/*/insmod.sh`.

Code `port.sh` + các step còn lại là của repo này.
