# Finmi branding

These approved wallet/coin images are copied unchanged from the supplied Finmi
App Kit. Runtime assets are declared in `pubspec.yaml`; no external folder or
machine-specific path is required.

- `logo.png`: application header and account branding.
- `banner.png`: home page banner.
- `background-dark.png`: login and registration background.
- `icon.png`: source for the committed Android, iOS and web launcher icons.
  It is a tooling input and is not bundled as an additional runtime image.

On Windows, regenerate platform icons from the project root with:

```powershell
powershell -NoProfile -File tool/generate_finmi_icons.ps1
```

The Be Vietnam Pro font files and their OFL license are in `assets/fonts/`.
