# AGENTS

This repo packages the Grok Build Windows desktop app (designed icon + launcher + shortcuts).

If the user asked you to install this package:

1. Read `README_AI.md`.
2. On Windows, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1` from the repo root.
3. Report the installer summary. Do not ask the user to run the installer.

Do not commit secrets. Do not copy `auth.json` or `config.toml` into this repo. Do not add `grok.exe` to this repo.
