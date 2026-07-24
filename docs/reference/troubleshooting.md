# Troubleshooting

Common issues and their solutions.

## Installation Issues

### "Cannot find script" during Bootstrap

**Problem:** PowerShell can't find the bootstrap script.

**Solution:**

```powershell
# Run with explicit path
iex (irm "https://raw.githubusercontent.com/IvanPavlak/WinuX/master/Windows/WinuX/WinuX.ps1")

# Or if locally:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
. .\Windows\WinuX\WinuX.ps1
```

### Execution Policy Error

**Problem:** "Running scripts is disabled on this system"

**Solution:**

```powershell
# For current session only (safe)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Or permanently (run as admin)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Git Not Found

**Problem:** Bootstrap fails because Git isn't installed.

**Solution:**

```powershell
# Install Git first
winget install Git.Git

# Restart terminal, then run Bootstrap
Bootstrap -WithInitialSetup
```

### WinGet Not Found

**Problem:** WinGet is not available on the system.

**Solution:**

```powershell
# Bootstrap auto-installs WinGet via Install-WinGetPackageManager
# Or manually from Microsoft Store: "App Installer"
```

### WinGet Install Hangs During Unattended / VM Bootstrap

**Problem:** On a fresh machine - most often a VM or the elevated bootstrap console - `Install-WingetApps` appears to hang and installs nothing, even though `winget` is present.

**Cause:** The `msstore` source shows a hard, one-time agreement (including a geographic-region consent) the first time that source is **queried**. Only `--accept-source-agreements` clears it - `--disable-interactivity` does not suppress this legal gate. In an unattended, non-interactive console nobody can answer the prompt, so the first call that engages msstore blocks forever. The `-s winget` installs never accept the msstore agreement, and a bare `winget list` does not engage msstore on a fresh machine, so the acceptance is never recorded.

**Solution:** This is handled automatically - before installing anything, `Install-WingetApps` queries each source (`winget` and `msstore`) directly with `--accept-source-agreements`, which forces the agreement to surface and records the acceptance for every later install. If a hang persists, your WinGet predates 1.6 (which introduced `--disable-interactivity`); update **App Installer** from the Microsoft Store, then re-run:

```powershell
# One-time manual acceptance of the msstore agreement (querying the source is what triggers it)
winget search example --source msstore --accept-source-agreements --disable-interactivity
Install-WingetApps
```

## Configuration Issues

### Machine Type Not Detected

**Problem:** `$MachineType` is empty or wrong.

**Solution:**

1. Check hostname mapping in `Configuration.psd1`:

```powershell
HostnameToMachineType = @{
    "YourHostname" = "PC"  # Add your mapping
}
```

2. Verify hostname:

```powershell
hostname
```

3. Set hostname if needed:

```powershell
Rename-Machine -NewName "DESKTOP-GAMING"
# Requires restart
```

### Path Not Expanding

**Problem:** Paths show `{Dev}` instead of actual path.

**Solution:**

1. Check `BasePaths` has your machine type:

```powershell
BasePaths = @{
    PC = @{ Dev = "C:\Users\You\Development\GitHub"; User = "C:\Users\You" }
    # Add your machine type if missing
}
```

2. Reload profile:

```powershell
Reload-PowerShellProfile
```

### Invalid Configuration Syntax

**Problem:** PowerShell errors when loading profile.

**Solution:**

```powershell
# Run Pester tests to validate
Run-Tests

# Common issues:
# - Missing closing brace }
# - Missing comma between array items
# - Invalid escape sequences
```

## Symbolic Link Issues

### "A required privilege is not held"

**Problem:** Can't create symbolic links.

**Solution:**

```powershell
# Enable Developer Mode
Enable-DeveloperMode

# Or manually: Settings → Privacy & security → For developers → Developer Mode
```

### Symlink Points to Wrong Target

**Problem:** Symlink exists but points to old location.

**Solution:**

```powershell
# Remove and recreate
Remove-Item "C:\Path\To\Symlink" -Force
SymbolicLinkMaker
```

### WSL Symlink Fails

**Problem:** WSL symlinks not created.

**Solution:**

1. Ensure WSL is installed:

```powershell
wsl --list
```

2. Check target exists in WinuX:

```powershell
Test-Path "WinuX\Server\.ssh\config"
```

3. Create target path in WSL:

```bash
wsl mkdir -p /home/you/.ssh
```

## Application Launch Issues

### "WhatsApp is already running!" With No WhatsApp Window

**Problem:** `Open-WhatsApp` (directly, or as a workspace action) reports `WhatsApp is already running!` and opens nothing, even though no WhatsApp window is on screen. It happens intermittently - sometimes the same workspace opens WhatsApp fine.

**Why it happens:** When a WhatsApp notification arrives while the app is closed, Windows COM-activates a background push notification host: `WhatsApp.Root.exe -RegisterForBGTaskServer /nowindow /pushnotification -Embedding`. That host owns no visible window, but it runs under the same `WhatsApp.Root` process name the UI does, so a process-name-only check treats it as a running app. It is intermittent because the host only exists once Windows has activated it, and `Kill-All` only clears it until the next notification.

**Solution:** This is handled - `Open-WhatsApp` passes `-RequireMainWindow` to `Start-Application`, so only a process owning a visible main window counts as running. To inspect the state yourself:

```powershell
# A background-only host shows MainWindowHandle 0; a real UI shows a non-zero handle
Get-Process WhatsApp.Root | Select-Object Id, MainWindowHandle, MainWindowTitle

# Confirm it is the push notification host
Get-CimInstance Win32_Process -Filter "Name = 'WhatsApp.Root.exe'" | Select-Object CommandLine
```

The same `-RequireMainWindow` switch applies to any app that keeps a windowless helper alive under its own process name.

## Window Layout Issues

### Windows Not Positioning

**Problem:** `Set-WorkspaceWindowLayout` doesn't move windows.

**Solutions:**

1. Check process name is correct:

```powershell
Get-ActiveWindowInfo  # Focus the window, see actual process name
```

2. Check window title pattern:

```powershell
# Use wildcards for flexibility
WindowTitle = "*Visual Studio Code"  # Ends with
WindowTitle = "*Mozilla Firefox*"    # Contains
```

3. Ensure window is open before applying layout:

```powershell
# Layout actions should come last in workspace actions
```

4. Run with verbose/debug output:

```powershell
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName "MyOrg" }
```

### "The RPC server is unavailable. (0x800706BA)" During Workspace Setup

**Problem:** Virtual desktop operations (`Ensure-VirtualDesktops`, `Remove-VirtualDesktops`, `Switch-Desktop`) fail with `The RPC server is unavailable. (0x800706BA)` - typically after Explorer restarted earlier in the session (taskbar configuration, icon-cache rebuild, theme changes), and re-importing the `VirtualDesktop` module doesn't help.

**Why it happens:** The `VirtualDesktop` module creates its COM connections to Explorer once per PowerShell process (in a compiled static constructor) and caches them. When Explorer restarts, those cached connections are permanently severed for that session; because the compiled assembly stays loaded, `Remove-Module` + `Import-Module` never re-creates them.

**Solution:** This now self-heals. Workspace commands probe the session's live COM state before desktop work and reconnect it in place (`Reset-VirtualDesktopState` rebuilds the cached COM proxies via `Reset-VirtualDesktopComProxy`); `Restart-Explorer` reconnects proactively after restarting the shell. If a session still reports RPC errors, reconnect manually:

```powershell
# Reconnect this session's VirtualDesktop COM state in place
Reset-VirtualDesktopState

# Inspect the live state directly
Test-VirtualDesktopComHealth
```

Opening a new shell also works (a fresh process builds fresh COM connections), but is no longer necessary.

### FancyZones Not Running

**Problem:** Zone snapping doesn't work.

**Solution:**

```powershell
Start-FancyZones

# Stronger recovery path (recommended for stubborn snap failures)
Start-FancyZones -ForceRestart -MaxWaitSeconds 20

# Or restart PowerToys
Stop-Process -Name "PowerToys" -Force
Start-Process "C:\Program Files\PowerToys\PowerToys.exe"
```

`Set-WorkspaceWindowLayout` rerun recovery now performs this forced restart path automatically and avoids duplicate back-to-back restarts across reruns.

### FancyZones Snap Fails With Custom Spacing

**Problem:** `Snap-AllWindows` fails to verify snap positions or snaps windows to wrong zones after changing the `spacing` value in `custom-layouts.json`.

**Solution:** Set `spacing` to `3` in all layouts within `FancyZones/custom-layouts.json`:

```json
"show-spacing": true,
"spacing": 3,
"sensitivity-radius": 20
```

**Why:** FancyZones internally applies spacing asymmetrically - full spacing on outer grid edges (first/last row and column), half spacing on inner edges. The zone coordinate calculation uses a uniform approximation (`spacing / 2` on all edges). With `spacing: 3`, the maximum error is ~2px (within the 20px snap tolerance). Larger values (e.g. 10, 20) cause up to 10-20px mismatches per dimension, exceeding tolerance and causing snap verification failures.

If a workspace layout reruns after a snap failure, the recovery path now resizes only the failed window handle before retrying. Other open windows are left untouched.

### Layout File Not Found

**Problem:** "Cannot find layout file" error.

**Solution:**

1. Check file exists for your machine type:

```
Modules/Window/Layouts/PC/WorkspaceName_PC.psd1
```

2. Check machine type:

```powershell
$MachineType  # Should match folder name
```

## Browser Issues

### URLs Not Opening

**Problem:** `Open-Browser` does nothing.

**Solutions:**

1. Check browser is installed:

```powershell
Get-Command firefox -ErrorAction SilentlyContinue
```

2. Check browser groups exist:

```powershell
$Configuration.BrowserGroups
```

3. Try with explicit browser:

```powershell
Open-Browser AI -Browser Chrome
```

### Duplicate Group Names

**Problem:** Wrong URL opens.

**Solution:**
All names must be unique across all groups:

```powershell
# Bad - "Profile" used twice
@{ Personal = @( @{ Name = "Profile"; Url = "..." } )}
@{ Work = @( @{ Name = "Profile"; Url = "..." } )}

# Good - Unique names
@{ Personal = @( @{ Name = "PersonalProfile"; Url = "..." } )}
@{ Work = @( @{ Name = "WorkProfile"; Url = "..." } )}
```

## Git Issues

### Authentication Failed

**Problem:** `Update-Repositories` fails with auth error.

**Solution:**

```powershell
# Configure credential manager
git config --global credential.helper manager

# Or re-authenticate
gh auth login
```

### Repository Not Found

**Problem:** "Repository not found" error.

**Solution:**

1. Check URL is correct in `Universal.GitHub`:

```powershell
Private = @{
    WinuX = "/YourUsername/WinuX.git"  # Check username
}
```

2. For private repos, ensure you have access.

## Performance Issues

### Slow Profile Load

**Problem:** New terminal takes long to start.

**Solutions:**

1. Check for slow modules:

```powershell
Measure-Command { . $PROFILE }
```

2. Lazy load non-essential functions.

3. Check for slow network operations during load.

### High Memory Usage

**Problem:** PowerShell using too much RAM.

**Solution:**

```powershell
# Start fresh session
exit
# Open new terminal
```

## Debugging Commands

### Validate Everything

```powershell
# Run the Pester test suite
Run-Tests

# Check specific function tests
Run-Tests Validate-Layout
Run-Tests Test-BrowserGroupAlreadyOpen
```

### Check Current State

```powershell
$MachineType                        # Current machine
$MachineSpecificPaths              # All expanded paths
$Configuration                     # All config
Get-ActiveWindowInfo               # Current window details
```

### Verbose Output

```powershell
Bootstrap -Verbose
Update-Repositories -Verbose
Set-LogLevel Verbose { Set-WorkspaceWindowLayout -WorkspaceName "X" }
```

## Getting Help

1. Run the test suite: `Run-Tests`
2. Check this troubleshooting guide
3. Review function documentation
4. Check GitHub issues
5. Enable verbose/debug mode for details

## See Also

- [Tests Module](../modules/tests.md)
- [Getting Started: Prerequisites](../getting-started/prerequisites.md)
