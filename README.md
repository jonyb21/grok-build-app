# Grok Build App

Windows desktop wrapper for [Grok Build](https://x.ai): designed spark icon, `GrokBuild.exe` launcher, Desktop and Start Menu shortcuts.

This is an unofficial wrapper. The Grok CLI itself is installed from x.ai. This repo does not ship `grok.exe` or credentials.

## Give this to an AI

Paste this (or point the agent at [README_AI.md](README_AI.md)):

```text
Install https://github.com/jonyb21/grok-build-app
Read README_AI.md and run install.ps1. Do not ask me to run it.
```

The copy-paste block also lives in [AI-INSTALL-PROMPT.md](AI-INSTALL-PROMPT.md).

## Install yourself (Windows)

```powershell
git clone https://github.com/jonyb21/grok-build-app.git
cd grok-build-app
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Grok plugin (skills only — still run `install.ps1` for the desktop app):

```text
grok plugin install jonyb21/grok-build-app --trust
```

## What you get

| Item | Location |
|------|----------|
| Launcher | `%USERPROFILE%\.grok\GrokBuild.exe` |
| Icon | `%USERPROFILE%\.grok\grok-build.ico` |
| Official CLI | `%USERPROFILE%\.grok\bin\grok.exe` |
| Desktop shortcut | `Desktop\Grok Build.lnk` |
| Start Menu | `Start Menu\Programs\Grok Build.lnk` |

First launch opens a browser to sign in at grok.com unless `auth.json` already exists.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes the wrapper, icon, and shortcuts. Leaves the official CLI, `auth.json`, and `config.toml` alone.

## Layout

```text
install.ps1                         AI / human installer
uninstall.ps1
README_AI.md                        Agent bootstrap
AI-INSTALL-PROMPT.md                Prompt to paste to another AI
src/GrokBuildLauncher.cs            Desktop wrapper
src/SetShortcutAppId.cs             Shortcut AppUserModelID helper
assets/grok-build-app-icon.png      Designed app icon
skills/install-grok-build-app/      Grok skill
.grok-plugin/plugin.json
```
