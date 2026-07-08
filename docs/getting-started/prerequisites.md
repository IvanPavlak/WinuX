# Prerequisites

Before running WinuX, ensure your system meets the following requirements:

> [!WARNING]
> These scripts have been comprehensively tested across multiple environments - VMware, a personal PC, a personal laptop, and a work laptop - with no system-breaking problems detected. Even so, apply your own judgment when using them.

## System Requirements

| Requirement              | Details                                                                |
| ------------------------ | ---------------------------------------------------------------------- |
| **Operating System**     | Windows 11                                                             |
| **Administrator Access** | Required - the installer creates symlinks and modifies system settings |
| **Internet**             | Required for downloading packages and cloning repos                    |
| **WinGet**               | Comes pre-installed on Windows 11 via App Installer                    |

> [!NOTE]
> **PowerShell version doesn't matter.** If you're running PowerShell 5.x (the Windows default), the installer automatically installs PowerShell 7 via WinGet and relaunches itself.

> [!NOTE]
> **Nothing else needs pre-installing.** Bootstrap provisions every tool the engine depends on: the WinGet app set (Windows Terminal, PowerShell 7, Oh My Posh, fastfetch, VS Code, Firefox, PowerToys), Git via `Install-Git`, the pinned `VirtualDesktop` 1.5.11 and the other PowerShell modules via `Install-PowerShellModules`, and the JetBrainsMono Nerd Font. In particular `fastfetch` and the `VirtualDesktop` module - which the profile and window management rely on - are bootstrap-installed, not prerequisites (the CI test suite stubs them for the same reason).

## Hostname Configuration

WinuX detects each machine's type from its hostname via `Configuration.psd1 →
HostnameToMachineType`. The shipped configuration defines only the `Test` type; you add your
own types and hostname mappings as you adopt WinuX (see
[Machine Types](../configuration/machine-types.md)). For example:

```
DESKTOP-GAMING  → MachineType → PC
LAPTOP-PERSONAL → MachineType → Laptop
WORKSTATION-01  → MachineType → Work
Test            → MachineType → Test
```

> [!TIP]
> If your hostname doesn't match, nothing fails: WinuX falls back to the default machine type
> (`Test` in the shipped configuration), and the first run's `Rename-Machine` step asks whether
> you want to rename the machine. You can also rename it yourself:
>
> ```powershell
> Rename-Computer -NewName "DESKTOP-GAMING" -Restart
> ```
>
> After initial setup, the [`Rename-Machine`](../modules/system.md#rename-machine) function from the [System module](../modules/system.md) is also available.

## How to Check/Change Hostname

```powershell
# Check current hostname
hostname

# Rename (requires restart)
Rename-Computer -NewName "DESKTOP-GAMING" -Restart
```

## Optional: GitHub Personal Access Token

If your WinuX repository is **private**, you'll need a GitHub PAT:

1. Go to GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Generate new token with `repo` scope (Full control of private repositories)
3. Save securely (e.g., in some password manager) - you'll need it during installation

> [!WARNING]
> Never commit your PAT to any repository!

## Next Steps

Ready to install? Continue to [Installation](installation.md).
