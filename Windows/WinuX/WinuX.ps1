# ==============================================================================
# WinuX installer entry point - the source compiled into WinuX.exe.
#
# WinuX.exe is NOT committed: New-WinuXExecutable.ps1 (next to this file) compiles it, and
# .github/workflows/release.yml attaches a fresh build to every tagged GitHub release, so the
# newest installer always lives at <repo>/releases/latest/download/WinuX.exe.
#
# ps2exe-compiled executables host the Windows PowerShell 5.1 engine, so everything in this
# file must stay 5.1-compatible - PowerShell 7 is installed and relaunched into further down
# the chain, never required here.
#
# What running it does:
#   * Standalone (Desktop, Downloads, USB stick, fresh machine) - fetches Install-Bootstrap.ps1
#     from WINUX_REPO_URL (default: the public WinuX repository) and hands over to it.
#     The fetch is tried anonymously first; when that fails (private repository or fork) a
#     GitHub PAT is prompted for and sent as a Bearer header - the exact flow documented in
#     docs/getting-started/installation.md. Install-Bootstrap then handles PowerShell 7,
#     elevation, clone-or-pull, and Bootstrap -WithInitialSetup.
#   * From inside a WinuX clone (<root>\Windows\WinuX\) - the machine already has WinuX, so
#     the download is skipped entirely and an elevated PowerShell 7 is relaunched running
#     Bootstrap -WithInitialSetup against that clone: the same reprovisioning
#     Install-Bootstrap ends with, minus the network round-trip and the PAT.
#
# WINUX_REPO_URL / WINUX_BRANCH (and the other WINUX_* variables Install-Bootstrap reads) can
# be set before launching to target a fork or a branch; unset, the defaults below apply.
# ==============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# New-WinuXExecutable.ps1 -RepoUrl rewrites this line at build time, so a fork's release
# workflow produces an executable that installs the fork - the committed default stays the
# public WinuX repository.
$DefaultRepoUrl = 'https://github.com/IvanPavlak/WinuX.git'

function Get-EntryPointDirectory {
	# Inside a ps2exe-compiled executable $PSCommandPath/$PSScriptRoot are empty - the process
	# path is the only reliable way to locate the running WinuX.exe. Run as a plain .ps1 the
	# script variables work (and the process path would point at powershell.exe instead).
	if ($PSCommandPath) {
		return Split-Path -Path $PSCommandPath -Parent
	}

	try {
		$processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
		return Split-Path -Path $processPath -Parent
	}
	catch {
		return $null
	}
}

function Find-LocalRepositoryRoot {
	# The machine counts as "already has WinuX" ONLY when this file runs from its committed
	# location inside a clone (<root>\Windows\WinuX\): two levels up must hold the Bootstrap
	# module manifest. A standalone copy (Desktop, Downloads, USB) never matches and follows
	# the installer path instead - still safe on an already-provisioned machine, because
	# Install-Bootstrap pulls rather than clones when the target folder exists.
	param([string]$Directory)

	if ([string]::IsNullOrWhiteSpace($Directory)) { return $null }

	$parent = Split-Path -Path $Directory -Parent
	if ([string]::IsNullOrWhiteSpace($parent)) { return $null }

	$root = Split-Path -Path $parent -Parent
	if ([string]::IsNullOrWhiteSpace($root)) { return $null }

	$manifest = Join-Path -Path $root -ChildPath 'Windows\PowerShell\Modules\Bootstrap\Bootstrap.psd1'
	if (Test-Path -Path $manifest) { return $root }

	return $null
}

function Start-LocalBootstrap {
	# Relaunch an elevated PowerShell 7 that runs the same reprovisioning Install-Bootstrap
	# ends with. Mirrors Start-PowerShell7WithAuth in Install-Bootstrap.ps1 (-EncodedCommand
	# survives quoting across the UAC boundary).
	#
	# The child session is -NoProfile, so it must recreate the module environment the profile
	# normally provides (and that Bootstrap assumes): the clone's Modules folder prepended to
	# PSModulePath so every repo module autoloads by name (Bootstrap calls into Helper, System,
	# Application, ... before and after Load-PathConfiguration), then - like the profile -
	# Logging imported first (unified logging from the very start) and Bootstrap imported
	# explicitly. The verb warning is silenced exactly as the profile does.
	param([string]$RepoRoot)

	$pwsh = Get-Command -Name pwsh -ErrorAction SilentlyContinue
	if (-not $pwsh) {
		# A clone without PowerShell 7 means the machine was never provisioned - the full
		# installer knows how to fix that (it installs PowerShell 7, then pulls this clone
		# when it sits at the configured install path).
		return $false
	}

	$command = @"
try {
	Set-ExecutionPolicy Bypass -Scope Process -Force
	`$WarningPreference = 'SilentlyContinue'
	`$env:PSModulePath = '$RepoRoot\Windows\PowerShell\Modules;' + `$env:PSModulePath
	Import-Module -Name Logging -Force -Global
	Import-Module -Name Bootstrap -Force -Global
	Bootstrap -RepoRoot '$RepoRoot' -WithInitialSetup
}
catch {
	Write-Host -ForegroundColor Red "``n=> Bootstrap failed => `$(`$_.Exception.Message)"
	Read-Host -Prompt 'Press Enter to close' | Out-Null
}
"@

	$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
	Start-Process -FilePath $pwsh.Source -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand -Verb RunAs -ErrorAction Stop

	Write-Host -ForegroundColor DarkCyan "`n=> Launched PowerShell 7 as Administrator! This window will now close!"
	Start-Sleep 5
	return $true
}

function Get-RepositoryCoordinates {
	# Resolve owner/repository/branch from the WINUX_* environment (fork/branch overrides) or
	# fall back to the public defaults - the same parsing Install-Bootstrap.ps1 uses for its
	# elevated relaunch. WINUX_REPO_URL is (re)exported so Install-Bootstrap's configuration
	# resolution sees exactly what was resolved here.
	$repoUrl = if ([string]::IsNullOrWhiteSpace($env:WINUX_REPO_URL)) { $DefaultRepoUrl } else { $env:WINUX_REPO_URL }
	$branch = if ([string]::IsNullOrWhiteSpace($env:WINUX_BRANCH)) { 'master' } else { $env:WINUX_BRANCH }

	if ($repoUrl -notmatch 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?/?$') {
		Write-Error "Cannot parse a GitHub owner/repository from WINUX_REPO_URL => [$repoUrl]" -ErrorAction Stop
	}

	$env:WINUX_REPO_URL = $repoUrl

	return @{
		Owner      = $matches[1]
		Repository = $matches[2]
		Branch     = $branch
		ScriptUrl  = "https://raw.githubusercontent.com/$($matches[1])/$($matches[2])/$branch/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1"
	}
}

function Test-HttpResponseError {
	# True when the fetch failed because GitHub ANSWERED with an HTTP error (401/403/404 - a
	# private repository, a rejected token, or a wrong owner/repository/branch); false when the
	# request never reached GitHub (DNS, no network, captive portal, proxy, timeout) - failures
	# a PAT can never fix. Engine-proof: WebException (Windows PowerShell 5.1, what the
	# compiled executable hosts) and HttpResponseException (PowerShell 7) both expose .Response
	# only when a response exists; transport exceptions have none.
	param([System.Management.Automation.ErrorRecord]$ErrorRecord)

	return ($null -ne $ErrorRecord.Exception.Response)
}

function Request-NetworkRetry {
	# The machine could not reach raw.githubusercontent.com at the transport level - typical on
	# a fresh machine that is not online yet (Wi-Fi not connected, captive portal, VPN/proxy).
	# Let the user fix the connection and retry in place instead of restarting the installer;
	# quitting aborts through a terminating error the main catch reports.
	param([System.Management.Automation.ErrorRecord]$ErrorRecord)

	Write-Host -ForegroundColor Yellow "`n=> Cannot reach raw.githubusercontent.com => $($ErrorRecord.Exception.Message)"
	Write-Host -ForegroundColor Yellow "   This is a network problem, not an authentication one. Check the internet connection (Wi-Fi, cable, captive portal, VPN/proxy), then retry."

	$answer = Read-Host -Prompt "Press Enter to retry or type [Q] to quit"
	if ($answer -and $answer.Trim() -match '^[qQ]') {
		Write-Error "Installation aborted - raw.githubusercontent.com is unreachable." -ErrorAction Stop
	}
}

function Get-InstallerScript {
	# Fetch Install-Bootstrap.ps1 - anonymously first (public repository), then with a prompted
	# PAT as a Bearer header (private repository or fork). Transport failures (offline machine)
	# get a fix-and-retry loop at every step; only an actual HTTP rejection from GitHub moves
	# the flow to the PAT prompt (anonymous fetch) or re-prompts (rejected token). The PAT is
	# kept in $global:Token as a SecureString so the fetched script's own trailing invocation
	# picks it up via Get-Variable and reuses it for the authenticated clone - identical to the
	# documented private one-liner.
	param([hashtable]$Coordinates)

	Write-Host -ForegroundColor DarkCyan "`n[Fetching the WinuX installer]"
	Write-Host -ForegroundColor DarkCyan "   Repository => https://github.com/$($Coordinates.Owner)/$($Coordinates.Repository) [$($Coordinates.Branch)]"

	while ($true) {
		try {
			return Invoke-RestMethod -Uri $Coordinates.ScriptUrl
		}
		catch {
			if (Test-HttpResponseError -ErrorRecord $_) {
				Write-Host -ForegroundColor Yellow "`n=> Anonymous download rejected (HTTP $([int]$_.Exception.Response.StatusCode)) - the repository is private, or the owner/repository/branch does not exist."
				Write-Host -ForegroundColor Yellow "   A GitHub Personal Access Token (PAT) with the [repo] scope is required for a private repository."
				break
			}
			Request-NetworkRetry -ErrorRecord $_
		}
	}

	$global:Token = Read-Host -Prompt "Paste your GitHub Personal Access Token (PAT)" -AsSecureString
	$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
		[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($global:Token)
	)

	if ([string]::IsNullOrWhiteSpace($plainToken)) {
		Write-Error "No token entered - cannot download from a private repository." -ErrorAction Stop
	}

	while ($true) {
		try {
			return Invoke-RestMethod -Uri $Coordinates.ScriptUrl -Headers @{ Authorization = "Bearer $plainToken" }
		}
		catch {
			if (-not (Test-HttpResponseError -ErrorRecord $_)) {
				# Offline again (or still) - the token is fine, keep it and retry the fetch.
				Request-NetworkRetry -ErrorRecord $_
				continue
			}

			Write-Host -ForegroundColor Yellow "`n=> GitHub rejected the token (HTTP $([int]$_.Exception.Response.StatusCode)) - it must have the [repo] scope and access to [$($Coordinates.Owner)/$($Coordinates.Repository)], and the branch [$($Coordinates.Branch)] must exist."
			$global:Token = Read-Host -Prompt "Paste a valid GitHub Personal Access Token (PAT), or press Enter to quit" -AsSecureString
			$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
				[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($global:Token)
			)

			if ([string]::IsNullOrWhiteSpace($plainToken)) {
				Write-Error "No token entered - cannot download from a private repository." -ErrorAction Stop
			}
		}
	}
}

try {
	Write-Host -ForegroundColor DarkCyan "[WinuX]"

	$localRoot = Find-LocalRepositoryRoot -Directory (Get-EntryPointDirectory)

	if ($localRoot) {
		Write-Host -ForegroundColor Yellow "`n=> Existing WinuX found at [$localRoot] - reprovisioning it, no download needed!"
		if (Start-LocalBootstrap -RepoRoot $localRoot) { exit 0 }
		Write-Host -ForegroundColor Yellow "`n=> PowerShell 7 not found - falling back to the full installer!"
	}

	$coordinates = Get-RepositoryCoordinates
	$installer = Get-InstallerScript -Coordinates $coordinates

	if ([string]::IsNullOrWhiteSpace($installer)) {
		Write-Error "The downloaded installer is empty - aborting." -ErrorAction Stop
	}

	# Install-Bootstrap.ps1 is written for the default (Continue) semantics of an interactive
	# one-liner - restore them so iex runs it exactly as `irm ... | iex` would.
	$ErrorActionPreference = 'Continue'
	Invoke-Expression $installer
}
catch {
	Write-Host -ForegroundColor Red "`n=> WinuX installation failed => $($_.Exception.Message)"
	Read-Host -Prompt "Press Enter to exit" | Out-Null
	exit 1
}
