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
- **Scale:** the undocumented `DisplayConfigSetDeviceInfo` request type `-4` sets the DPI scale of the primary display
  (the Settings app uses the same call). Supported values are the standard steps such as 175% and 225%.
- **Verification:** after setting, each script reads both values back. On any mismatch or failure it shows a message
  box ("Display Modes") instead of failing silently.
- **Idempotent:** running a mode that is already active changes nothing.
- **Risk:** the scale call is undocumented, so a future Windows update may break it. If that happens the message box
  says the scale could not be set; auto-hide keeps working independently.
- **`ShowFatal.ps1`:** a small, dependency-free message-box helper used by `Compact.ps1` and `Roomy.ps1` for any failure,
  including `DisplayModes.ps1` itself failing to load. `DisplayModes.ps1` holds the actual getters and setters.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-DisplayModes.ps1
```

The tests run against the real machine: they visibly rescale the screen and toggle taskbar auto-hide, then restore the
original state when finished. The shortcut installer test works on a temporary copy, so it never touches your `.lnk` files.
