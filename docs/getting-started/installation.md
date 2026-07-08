# Installation

WinuX can be installed with a **single command** that bootstraps your entire system from
scratch. Everything is driven by your configuration - **you never edit code** to install it.

> [!WARNING]
> The installer runs as **Administrator** and makes broad, state-changing modifications
> (installs software, creates symlinks, reconfigures the OS). **Evaluate WinuX in a virtual
> machine first**, and read [`Install-Bootstrap.ps1`](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1)
> before running it (see the [Security Policy](https://github.com/IvanPavlak/WinuX/security)).

## One-liner installation

Paste the matching command into an **Administrator** Windows Terminal (PowerShell). If you are
on Windows PowerShell 5.1, WinuX installs PowerShell 7 and relaunches itself elevated
automatically.

### Install the official WinuX (public - recommended)

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $env:WINUX_REPO_URL = 'https://github.com/IvanPavlak/WinuX.git'; irm 'https://raw.githubusercontent.com/IvanPavlak/WinuX/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' | iex
```

You will be prompted once for your Git `user.name` and `user.email` (used only for your local
Git config - never committed). A fork that commits a `Configuration.local.psd1` with a
`GitConfig` identity is not prompted at all - WinuX reads it from your repo after cloning.

### Install your own fork (public)

Replace `<owner>`/`<repo>` with your fork. WinuX clones **your** repository and uses **your**
`Configuration.psd1`:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $env:WINUX_REPO_URL = 'https://github.com/<owner>/<repo>.git'; irm 'https://raw.githubusercontent.com/<owner>/<repo>/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' | iex
```

### Install a private fork (with a Personal Access Token)

For a private repository, supply a GitHub PAT (with the `repo` scope). It is read into a
`SecureString`, sent only as a `Bearer` header to fetch the script, and used in-memory to
clone - it is never stored or logged:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $env:WINUX_REPO_URL = 'https://github.com/<owner>/<repo>.git'; $Token = Read-Host -Prompt "Paste your GitHub Personal Access Token (PAT)" -AsSecureString; irm 'https://raw.githubusercontent.com/<owner>/<repo>/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' -Headers @{ "Authorization" = "Bearer $([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)))" } | iex
```

### Install from a specific branch

Set `$env:WINUX_BRANCH`. Works with any of the modes above (add the PAT header for a private
branch):

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $env:WINUX_REPO_URL = 'https://github.com/<owner>/<repo>.git'; $env:WINUX_BRANCH = 'your-branch'; irm "https://raw.githubusercontent.com/<owner>/<repo>/$($env:WINUX_BRANCH)/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1" | iex
```

### Install a private fork from a specific branch

Combine the PAT header with the branch. The fetch URL is **double-quoted** so
`$($env:WINUX_BRANCH)` expands to the branch name - single-quoting it sends the literal text
`$($env:WINUX_BRANCH)` to GitHub and returns a 404:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $env:WINUX_REPO_URL = 'https://github.com/<owner>/<repo>.git'; $env:WINUX_BRANCH = 'your-branch'; $Token = Read-Host -Prompt "Paste your GitHub Personal Access Token (PAT)" -AsSecureString; irm "https://raw.githubusercontent.com/<owner>/<repo>/$($env:WINUX_BRANCH)/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1" -Headers @{ "Authorization" = "Bearer $([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)))" } | iex
```

## Executable installation (WinuX.exe)

Prefer a double-clickable installer over a terminal? Every tagged release attaches a compiled
`WinuX.exe` (plus a `WinuX.exe.sha256` checksum), so the newest installer is always at:

**[github.com/IvanPavlak/WinuX/releases/latest/download/WinuX.exe](https://github.com/IvanPavlak/WinuX/releases/latest/download/WinuX.exe)**

Download it, double-click it, and approve the elevation prompt when the installer relaunches
itself. The executable is `WinuX.ps1` compiled by CI on every release (never committed - see
[`Windows/WinuX/ExecutableCreation.md`](https://github.com/IvanPavlak/WinuX/blob/master/Windows/WinuX/ExecutableCreation.md)),
and it decides by where it runs:

- **Standalone** (Desktop, Downloads, a USB stick, a fresh machine): performs the full
  first-time installation above. The installer download is anonymous for the public WinuX;
  for a **private** repository or fork it prompts for a GitHub PAT and retries with a
  `Bearer` header - the same flow as the private one-liner. An offline machine (no Wi-Fi
  yet, captive portal, VPN/proxy) gets a connect-and-retry prompt instead - a PAT is only
  ever requested when GitHub actually rejected the anonymous download.
- **Inside an existing clone** (`<repo>\Windows\WinuX\WinuX.exe`): skips the download and
  relaunches an elevated PowerShell 7 running `Bootstrap -WithInitialSetup` against that
  clone - reprovisioning, exactly what the installer would end with anyway.

The `WINUX_*` environment variables below work for the executable too when it is started from
a terminal that set them first (a plain double-click uses the defaults).

**No internet, or can't reach the release assets?** With a local clone you can build the
identical installer yourself:

```powershell
cd <repo>\Windows\WinuX
.\New-WinuXExecutable.ps1   # -> .\WinuX.exe
```

On a WinuX-provisioned machine this runs fully offline (Bootstrap already installed the
`ps2exe` module it compiles with); anywhere else the script installs `ps2exe` once from the
PowerShell Gallery. Details, including a no-script fallback, in
[`Windows/WinuX/ExecutableCreation.md`](https://github.com/IvanPavlak/WinuX/blob/master/Windows/WinuX/ExecutableCreation.md).

> [!NOTE]
> The executable is unsigned, so Windows SmartScreen may warn on first run - choose
> **More info → Run anyway**. To verify a download first:
> `(Get-FileHash .\WinuX.exe -Algorithm SHA256).Hash` must match the published
> `WinuX.exe.sha256` release asset.

## Configuration via environment variables

The bootstrap reads these optional variables (set them before the `irm` call). Anything not
provided is prompted for when running interactively - except the Git identity, which WinuX
reads from a committed `Configuration.local.psd1` (`GitConfig`) after cloning and only prompts
for when that is absent:

| Variable          | Purpose                                                                              | Default                     |
| ----------------- | ------------------------------------------------------------------------------------ | --------------------------- |
| `WINUX_REPO_URL`  | The WinuX repository to clone (HTTPS `.git` URL).                                    | _(prompted)_                |
| `WINUX_GIT_NAME`  | Your Git `user.name` (else read from a committed `Configuration.local.psd1`).        | _(config, else prompt)_     |
| `WINUX_GIT_EMAIL` | Your Git `user.email` (else read from a committed `Configuration.local.psd1`).       | _(config, else prompt)_     |
| `WINUX_DEV_PATH`  | Root development directory (the repo is cloned to `<WINUX_DEV_PATH>\GitHub\<repo>`). | `%USERPROFILE%\Development` |
| `WINUX_BRANCH`    | Branch to check out after cloning.                                                   | `master`                    |

## What Install-Bootstrap does

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INSTALL-BOOTSTRAP PROCESS                           │
├───────────────────────────────────────────────────────────────────────────-─┤
│  Step 1: Check PowerShell version                                           │
│  ├─→ If PowerShell 5.x: install PowerShell 7 via WinGet                     │
│  └─→ Relaunch elevated in PowerShell 7 (carrying WINUX_* + branch + PAT)    │
│                                                                             │
│  Step 2: Verify Administrator privileges                                    │
│  Step 3: Start logging (BootstrapLog_*.log on the Desktop)                  │
│                                                                             │
│  Step 4: Resolve first-run configuration                                    │
│  ├─→ Read WINUX_REPO_URL / WINUX_DEV_PATH (repo URL prompted if unset)      │
│  └─→ Git identity is NOT resolved here (read after clone; see Step 7)       │
│                                                                             │
│  Step 5: Install Git (merge driver + long paths)                            │
│  Step 6: Clone the repository (PAT-authenticated or public/anonymous)       │
│  Step 7: Resolve Git identity, set global user.name / user.email            │
│  ├─→ From your committed Configuration.local.psd1 if the fork ships one     │
│  └─→ else WINUX_GIT_*, the existing git config, or an interactive prompt    │
│  Step 8: Load the Bootstrap module → Bootstrap -WithInitialSetup            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Installation location

The repository is cloned to `<dev>\GitHub\<repo>`, where `<dev>` is `WINUX_DEV_PATH`
(default `%USERPROFILE%\Development`) and `<repo>` is derived from your `WINUX_REPO_URL`. For
the default install that is:

```
%USERPROFILE%\Development\GitHub\WinuX
```

## Machine types

WinuX's shipped configuration defines a machine type you can adapt:

| Machine type | Purpose                                                                                                                   |
| ------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `Test`       | A minimal, self-contained profile with just what the repository needs to run - ideal for trying WinuX in a virtual machine. |

The active machine type is chosen by matching your hostname in
`Configuration.psd1 → HostnameToMachineType`; if your hostname isn't listed, WinuX falls back
to `DefaultMachineType` (no need to rename your computer just to get started). Add more machine
types by following the [Add a New Machine](../configuration/guides/add-new-machine.md) guide.

## Troubleshooting installation

### "Running scripts is disabled on this system"

Run PowerShell as Administrator and allow local scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "This script must be run with Administrator privileges"

Right-click Windows Terminal → **Run as administrator**, then run the one-liner again.

### PowerShell 7 not installing

Ensure WinGet is available (`winget --version`). If not, install **App Installer** from the
[Microsoft Store](https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1).

### Authentication failed (private repo)

- Ensure your PAT has the `repo` scope and hasn't expired.
- Confirm `WINUX_REPO_URL` points at the correct private repository.

### "WINUX_REPO_URL is not set"

You ran the bootstrap non-interactively without setting `WINUX_REPO_URL`. Set it (see the
one-liners above) or run interactively to be prompted.

## What happens next

After `Install-Bootstrap` completes, the full Bootstrap module is loaded and
`Bootstrap -WithInitialSetup` runs automatically. See [First Run](first-run.md) for what
Bootstrap does.
