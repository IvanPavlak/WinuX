# WinuX.exe - How the Installer Executable Is Built and Released

`WinuX.exe` is [`WinuX.ps1`](WinuX.ps1) compiled with [ps2exe](https://github.com/MScholtes/PS2EXE).
The binary is **not committed** (`Windows/WinuX/WinuX.exe` is gitignored) - every tagged
release builds it fresh and attaches it to the GitHub release, so the newest installer is
always at:

```
https://github.com/IvanPavlak/WinuX/releases/latest/download/WinuX.exe
```

A `WinuX.exe.sha256` checksum file is published next to it.

## What the executable does

Compiled `WinuX.ps1` hosts the Windows PowerShell 5.1 engine (a ps2exe property - exactly what
a fresh Windows 11 machine has), and decides by where it runs:

- **Standalone** (Desktop, Downloads, USB, fresh machine): fetches `Install-Bootstrap.ps1`
  from `WINUX_REPO_URL` (default: the repository compiled in at build time) - anonymously
  first, then prompting for a GitHub PAT (`Bearer` header) when the repository is private -
  and hands over to it: PowerShell 7, elevation, clone-or-pull, `Bootstrap -WithInitialSetup`.
  Offline machines get a connect-and-retry prompt: transport failures (DNS, no network,
  captive portal) are distinguished from HTTP rejections and never trigger the PAT prompt.
- **Inside a WinuX clone** (`<root>\Windows\WinuX\`): skips the download and relaunches an
  elevated PowerShell 7 running `Bootstrap -WithInitialSetup` against that clone.

## Automated build and release (the normal path)

[`.github/workflows/release.yml`](../../.github/workflows/release.yml) runs on every `v*` tag:

1. Builds the executable with [`New-WinuXExecutable.ps1`](New-WinuXExecutable.ps1), stamping
   the tag's version into the version resource and compiling the workflow's own repository in
   as the default install source (so a fork's release installs the fork).
2. Writes the SHA-256 checksum file.
3. Extracts the tag's section from `CHANGELOG.md` as the release notes.
4. Creates the GitHub release with both assets attached (or, when the release was already
   created in the UI, just attaches the assets to it).

A manual `workflow_dispatch` run builds the executable as a workflow **artifact** without
releasing anything - useful to verify the build before tagging.

## Manual build (local repo - no GitHub, no release download needed)

Anyone with a clone of the repository can produce the executable themselves - the release
asset is a convenience, never a requirement. Typical reasons: an offline/air-gapped machine,
the release assets are unreachable, you want to verify that the published binary is what the
source produces, or you are building a fork's installer.

```powershell
cd <repo>\Windows\WinuX
.\New-WinuXExecutable.ps1 # dev build -> .\WinuX.exe (gitignored)
.\New-WinuXExecutable.ps1 -Version 0.1.0 -ChecksumPath .\WinuX.exe.sha256
.\New-WinuXExecutable.ps1 -RepoUrl 'https://github.com/you/YourFork.git'
```

Works from both Windows PowerShell 5.1 and PowerShell 7. The script never modifies the
committed `WinuX.ps1` (`-RepoUrl` rewrites `$DefaultRepoUrl` in a temporary copy only), and
the output lands next to the script, gitignored - a local build can never end up in a commit.

The only dependency is the `ps2exe` module:

- A machine **provisioned by WinuX already has it** (Bootstrap's `Install-PowerShellModules`
  installs ps2exe), so the build runs **fully offline** there.
- Otherwise the script installs it once from the PowerShell Gallery - that one step needs
  internet. For a machine with no internet at all, copy the `ps2exe` module folder from any
  other machine into `$HOME\Documents\PowerShell\Modules` (PowerShell 7) or
  `$HOME\Documents\WindowsPowerShell\Modules` (5.1) first - standard xcopy module deployment.

Without the helper script, the bare-metal equivalent is plain ps2exe (this skips the version
resource, the checksum file, and the `-RepoUrl` rewrite the script adds):

```powershell
Invoke-ps2exe -inputFile .\WinuX.ps1 -outputFile .\WinuX.exe -iconFile .\WinuXLogo.ico
```

A locally built executable is functionally identical to a released one (same source). Run it
from inside the clone and it reprovisions that clone without any network fetch - see
[What the executable does](#what-the-executable-does).

## SmartScreen and verification

The executable is unsigned, so Windows SmartScreen may warn on first run (**More info → Run
anyway**). Verify a download against the published checksum first:

```powershell
(Get-FileHash .\WinuX.exe -Algorithm SHA256).Hash   # must match WinuX.exe.sha256
```

## Optional: code-sign a local build

For environments that require signed binaries, create a self-signed code-signing certificate
and sign the executable (machines must trust the exported `.cer` for the signature to count):

```powershell
# 1. Create the certificate and export it
$Certificate = New-SelfSignedCertificate -Subject "CN=MyBootstrapPublisher, O=My Internal Tools" -Type CodeSigning -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(10)
$SecurePassword = ConvertTo-SecureString -String "<password>" -Force -AsPlainText
Export-PfxCertificate -Cert $Certificate -FilePath "C:\Path\To\BootstrapSignCert.pfx" -Password $SecurePassword   # private key - KEEP SAFE
Export-Certificate -Cert $Certificate -FilePath "C:\Path\To\BootstrapSignCert.cer"                                # public key - install on targets

# 2. Sign (signtool ships with the Windows SDK / ClickOnce SignTool)
& "C:\Program Files (x86)\Microsoft SDKs\ClickOnce\SignTool\signtool.exe" sign /f "C:\Path\To\BootstrapSignCert.pfx" /p <password> /fd SHA256 /d "WinuX" ".\WinuX.exe"
```
