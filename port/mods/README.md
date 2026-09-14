# port/mods — per-OS + universal mod scripts (empty skeleton)

Copy `*.sh` mod scripts from `Omni16/nothingsvn_xiaomi-toolbuild`
`bin/modfile/` here, keeping the layout:

- `OS1/` ← `bin/modfile/OS1/*.sh` (trừ `insmod.sh`)
- `OS2/` ← `bin/modfile/OS2/*.sh`
- `OS3/` ← `bin/modfile/OS3/*.sh`
- `MIUI/` ← `bin/modfile/MIUI14/*.sh`
- `universal/` ← `bin/modfile/Universal/*.sh` + `bin/modfile/UpdateFile/*.sh`
  (trừ `insfile.sh`/`insupdate.sh`)

`30-mods.sh` runs `mods/<OS>/*.sh` then `mods/universal/*.sh` with
`$IMG $DEVICE $OS $REGION $ANDROID` exported. Scripts must be idempotent
(check marker before append) and must not hardcode codenames — gate on
`$OS`/`$REGION` instead. Heavy APK blobs stay in the Nothing repo;
reference them by path, don't vendor them here.
