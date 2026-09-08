---
name: install-grok-build-app
description: >
  Install the Grok Build Windows desktop app from this package: designed
  spark icon, GrokBuild.exe launcher, Desktop and Start Menu shortcuts, and
  the official x.ai CLI if missing. Use when the user asks to install Grok
  Build, grok-build-app, the Grok Build desktop app, or provides
  github.com/jonyb21/grok-build-app.
---

# Install Grok Build App

Install the Windows desktop wrapper. Do not describe the steps and stop. Run them.

## Locate the package

1. If this skill is already on disk, `SKILL.md` lives at `<package>/skills/install-grok-build-app/SKILL.md`. The installer is `<package>/install.ps1`.
2. If the package is missing, clone `https://github.com/jonyb21/grok-build-app` and use that clone as `<package>`.
3. Read `<package>/README_AI.md` and follow it.

## Install (Windows)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<package>\install.ps1"
```

Non-Windows: install only the official CLI (`curl -fsSL https://x.ai/cli/install.sh | bash`) and report that the desktop wrapper is Windows-only.

## Rules

- Do not overwrite `%USERPROFILE%\.grok\auth.json` or `config.toml`.
- Do not add `grok.exe` to git.
- Taskbar pin failure is not an install failure.
- After the script exits, read `%USERPROFILE%\.grok\grok-build-app-install.json` and report its fields.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<package>\uninstall.ps1"
```
