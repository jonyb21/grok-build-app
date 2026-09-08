# Prompt to give another AI

Copy everything below the line and paste it to Grok, Claude, Codex, Cursor, or any other coding agent.

---

Install the Grok Build desktop app from GitHub.

Repo: https://github.com/jonyb21/grok-build-app

You are a coding agent. Do this now without asking me to run commands:

1. Clone https://github.com/jonyb21/grok-build-app (or `gh repo clone jonyb21/grok-build-app`) into a working directory.
2. Read README_AI.md at the repo root and follow it exactly.
3. On Windows run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`
4. Report: hostname, grok CLI path and version, GrokBuild.exe path, shortcut paths, taskbar pin result, and whether grok.com login is still needed.

Do not overwrite existing `%USERPROFILE%\.grok\auth.json` or `config.toml`.
Do not download unofficial grok.exe binaries. The official CLI installer is https://x.ai/cli/install.ps1 and only if grok.exe is missing.
