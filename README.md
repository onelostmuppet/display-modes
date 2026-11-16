# display-modes

Two PowerShell scripts that switch Windows between a compact and a roomy desktop layout, each with a pinnable shortcut.

| Mode | Taskbar auto-hide | Display scale |
|------|-------------------|---------------|
| Compact | On | 175% |
| Roomy | Off | 225% |

The switch is instant: no sign-out, no restart.

## Setup

1. Clone or copy this folder somewhere permanent.
2. Run the installer once from that folder:

   ```powershell
   powershell -ExecutionPolicy Bypass -File Install-Shortcuts.ps1
   ```

   It creates `Compact.lnk` and `Roomy.lnk` next to the scripts and prints where it wrote them.
   Each shortcut runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<script>"`.
3. Pin both shortcuts to the taskbar: right-click the `.lnk`, choose **Show more options**, then **Pin to taskbar**.
   Windows 11 only pins shortcuts whose target is an `.exe`; the target here is `powershell.exe`, so this works.
4. If you move or rename the folder, run the installer again. The shortcuts hold absolute paths, so they are
   machine-specific and git-ignored. Re-running is safe: it just overwrites them.

## How it works

- **Auto-hide:** `SHAppBarMessage` with `ABM_SETSTATE` sets the taskbar's auto-hide flag.
- **Scale:** the undocumented `DisplayConfigSetDeviceInfo` request type `-4` sets the DPI scale of the primary display,
  the same undocumented request used by community tools such as SetDPI. Only the scale steps the display reports as
  supported are accepted; anything else is rejected with an error listing the supported values.
- **Verification:** after setting, each script reads both values back. Both settings are attempted on every run (a
  failure in one does not skip the other), and any mismatch or failure is reported together in one "Display Modes" message box
  instead of failing silently.
- **Idempotent:** a setting that is already at the requested value is left untouched.
- **Risk:** the scale call is undocumented, so a future Windows update may break it. If that happens the message box
  says the display scale failed or did not apply. The auto-hide setter is a separate `SHAppBarMessage` call, so it is still
  attempted and reported on its own.
- **`ShowFatal.ps1`:** `DisplayModes.ps1` reports setting mismatches and setter errors itself (and holds the getters and
  setters). `ShowFatal.ps1` is a small, dependency-free message-box helper used by `Compact.ps1` and `Roomy.ps1` to cover
  anything that escapes, including `DisplayModes.ps1` failing to load.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-DisplayModes.ps1
```

The tests run against the real machine: they visibly rescale the screen and toggle taskbar auto-hide, then restore the
original state when finished. The shortcut installer test works on a temporary copy, so it never touches your `.lnk` files.
