---
description: "Add a symbolic link entry to Configuration.psd1 for syncing app config files."
argument-hint: "App name and config file paths (e.g., 'LazyGit config from AppData to WinuX')"
agent: "agent"
---

# Add Symbolic Link

Add a symbolic link entry to Configuration.psd1 using `Add-SymbolicLink`.

## Steps

1. Ask the user for:
    - **App name** (entry identifier)
    - **Single file or multiple files?**
    - For each file: **Path** (where the link goes) and **Target** (actual file in WinuX repo)

2. Use placeholders for paths:
    - `{User}` → `C:\Users\You`
    - `{AppData}` → `C:\Users\You\AppData\Roaming`
    - `{RepoRoot}` → WinuX repo root
    - `{MachineType}` → PC, Laptop, Work, Test

3. Call the configuration function:

**Single file:**

```powershell
Add-SymbolicLink -Name "MyApp" -Path "{AppData}\MyApp\config.json" -Target "{RepoRoot}\MyApp\config.json"
```

**Multiple files:**

```powershell
Add-SymbolicLink -Name "MyApp" -Links @(
    @{ Name = "Settings"; Path = "{AppData}\MyApp\settings.json"; Target = "{RepoRoot}\MyApp\settings.json" }
    @{ Name = "Config"; Path = "{AppData}\MyApp\config.yaml"; Target = "{RepoRoot}\MyApp\config.yaml" }
)
```

4. Remind user to run `SymbolicLinkMaker` to create the actual links (requires Developer Mode).
