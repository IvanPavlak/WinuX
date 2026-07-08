function Loading-Spinner {
	param(
		[Parameter(Mandatory = $true)]
		[scriptblock]$Function,

		[Parameter(Mandatory = $false)]
		[string]$Label = ""
	)

	$job = Start-Job -ScriptBlock $Function

	$symbols = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
	$delay = 50
	$i = 0

	Write-Host ""

	while ($job.State -eq "Running") {
		$symbol = $symbols[$i]
		Write-Host -NoNewline "`r$symbol $Label" -ForegroundColor DarkCyan
		Start-Sleep -Milliseconds $delay
		$i++
		if ($i -eq $symbols.Count) {
			$i = 0
		}
	}

	Write-Host ""
	Write-Host -NoNewline "`r"

	return Receive-Job -Job $job
}

function Install-PowerShell {
	Write-Host -ForegroundColor DarkCyan "`n[PowerShell 7 Configuration]"

	$pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue

	if (-not $pwshPath) {
		Write-Host -ForegroundColor Yellow "`n PowerShell 7 not found. Installing..."
		Write-Host -ForegroundColor DarkCyan "`n[Installing PowerShell 7]"

		Loading-Spinner -Function {
			winget install Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
		} -Label "Installing..."

		$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

		$verifyPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
		if ($verifyPwsh) {
			Write-Host -ForegroundColor Green "`n=> PowerShell 7 installed successfully!"
			return $true | Out-Null
		}
		else {
			Write-Host -ForegroundColor Red "`n=> PowerShell 7 installation failed!"
			return $false | Out-Null
		}
	}
	else {
		Write-Host -ForegroundColor Yellow "`n=> PowerShell 7 is already installed!"
		return $false | Out-Null
	}
}

function Start-PowerShell7WithAuth {
	param(
		[string]$PwshPath,
		[string]$TokenPlainText
	)

	Write-Host -ForegroundColor DarkCyan "`n[Restarting in PowerShell 7 with Administrator privileges]"

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

	# Resolve the repository owner/name (for the raw-content URL) from the same environment
	# variables the install one-liner set. Owner/repo must be known before any code runs.
	$branch = if ($env:WINUX_BRANCH) { $env:WINUX_BRANCH } else { "master" }
	$owner = $env:WINUX_REPO_OWNER
	$repo = $env:WINUX_REPO_NAME
	if (([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) -and $env:WINUX_REPO_URL) {
		if ($env:WINUX_REPO_URL -match 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?/?$') {
			$owner = $matches[1]
			$repo = $matches[2]
		}
	}
	if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
		Write-Error "Cannot determine the repository owner/name for the elevated relaunch. Set WINUX_REPO_URL (or WINUX_REPO_OWNER + WINUX_REPO_NAME) before running." -ErrorAction Stop
	}

	$scriptUrl = "https://raw.githubusercontent.com/$owner/$repo/$branch/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1"

	# Re-inject the configuration env vars (and branch) so they survive the elevated relaunch.
	$branchSetup = if ($env:WINUX_BRANCH) { "`$env:WINUX_BRANCH = '$($env:WINUX_BRANCH)'; " } else { "" }
	$envSetup = @(
		"`$env:WINUX_REPO_URL = '$($env:WINUX_REPO_URL)';"
		"`$env:WINUX_REPO_OWNER = '$owner';"
		"`$env:WINUX_REPO_NAME = '$repo';"
		"`$env:WINUX_GIT_NAME = '$($env:WINUX_GIT_NAME)';"
		"`$env:WINUX_GIT_EMAIL = '$($env:WINUX_GIT_EMAIL)';"
		"`$env:WINUX_DEV_PATH = '$($env:WINUX_DEV_PATH)';"
		"`$env:WINUX_INSTALL_DIR = '$($env:WINUX_INSTALL_DIR)';"
	) -join " "

	if ([string]::IsNullOrWhiteSpace($TokenPlainText)) {
		# Public / anonymous clone: no token, no Authorization header.
		$command = @"
${branchSetup}${envSetup}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
irm '$scriptUrl' | iex
"@
	}
	else {
		# Private clone: carry the PAT and send it as a Bearer header to fetch the script.
		$command = @"
${branchSetup}${envSetup}
`$global:GithubPat = '$TokenPlainText';
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
`$Headers = @{ 'Authorization' = 'Bearer ' + `$global:GithubPat };
irm '$scriptUrl' -Headers `$Headers | iex
"@
	}

	$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

	Start-Process -FilePath $PwshPath -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand -Verb RunAs

	Write-Host -ForegroundColor DarkCyan "`n=> Launched PowerShell 7 as Administrator! This window will now close!"

	Start-Sleep 5
	exit
}

function Test-AdminPrivileges {
	$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

	if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
		Write-Error "This script must be run with Administrator privileges! Please re-launch in an Administrator PowerShell session." -ErrorAction Stop
	}
}

function Start-Logging {
	$global:logPath = Join-Path -Path $env:USERPROFILE -ChildPath "Desktop\BootstrapLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
	$global:startTime = Get-Date
	Start-Transcript -Path $global:logPath -Append | Out-Null
	Write-Host -ForegroundColor DarkCyan "`n[Logging started]"
}

function Get-FirstRunConfiguration {
	Write-Host -ForegroundColor DarkCyan "`n[Resolving First-Run Configuration]`n"

	# Resolve ONLY what a clone genuinely needs before the repo exists: the repository URL and where
	# to put it. The Git identity is deliberately NOT resolved here - it is read from the cloned
	# repo's committed configuration afterwards (see Set-BootstrapGitIdentity), so a fork that commits
	# Configuration.local.psd1 provisions any machine, new ones included, with no identity prompt.
	# Nothing is hardcoded; the repo URL still comes from WINUX_REPO_URL or, interactively, a prompt.
	$repoUrl = $env:WINUX_REPO_URL
	$devBase = if ($env:WINUX_DEV_PATH) { $env:WINUX_DEV_PATH } else { Join-Path $env:USERPROFILE "Development" }

	$interactive = [Environment]::UserInteractive

	if ([string]::IsNullOrWhiteSpace($repoUrl)) {
		if ($interactive) {
			Write-Host -ForegroundColor Yellow "No WINUX_REPO_URL provided. Enter the WinuX repository to install:"
			$owner = Read-Host -Prompt "  GitHub owner/username"
			$repo = Read-Host -Prompt "  Repository name (press Enter for 'WinuX')"
			if ([string]::IsNullOrWhiteSpace($repo)) { $repo = "WinuX" }
			$repoUrl = "https://github.com/$owner/$repo.git"
		}
		else {
			Write-Error "WINUX_REPO_URL is not set. Set WINUX_REPO_URL (and optionally WINUX_GIT_NAME, WINUX_GIT_EMAIL, WINUX_DEV_PATH) before running, or run interactively to be prompted." -ErrorAction Stop
		}
	}

	$githubPath = Join-Path $devBase "GitHub"

	Write-Host -ForegroundColor DarkCyan "   Repository => $repoUrl"
	Write-Host -ForegroundColor DarkCyan "   Base Path  => $githubPath"

	return @{
		RepoUrl    = $repoUrl
		GithubPath = $githubPath
	}
}

function Install-Git {
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-Host -ForegroundColor DarkCyan "`n[Installing Git]"
		winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
		$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
	}
	Write-Host -ForegroundColor DarkCyan "`n[Configuring Git global settings]"
	# user.name / user.email are intentionally NOT set here. They are resolved and set later by
	# Set-BootstrapGitIdentity, AFTER the repo is cloned, so a fork's committed Configuration.local.psd1
	# can supply them without a prompt. git clone/checkout need no identity, only committing does.
	# Register the "ours" merge driver referenced by .gitattributes so a fork keeps its own personal
	# files (app lists, payloads) when it pulls upstream WinuX updates. Harmless anywhere else: it only
	# ever runs for files that carry the `merge=ours` attribute. Git refuses to auto-register a merge
	# driver from a cloned repo (a security boundary), so the installer does it once here.
	git config --global merge.ours.driver true
	# Enable long paths so repositories with very long filenames (e.g. the Obsidian vault) can be
	# cloned later by Bootstrap -> Update-Repositories. Set system-wide here (we are elevated) so it
	# persists for every subsequent git operation. Mirrors the module Install-Git.
	git config --system core.longpaths true
}

function Get-ConfiguredGitIdentity {
	# Best-effort read of a committed Git identity from the cloned repo's configuration. A fork that
	# commits Configuration.local.psd1 (identity + paths) can then provision any machine - new ones
	# included - without a prompt or WINUX_GIT_* env vars. The local override wins over the generic
	# base (appsettings.Development style). WinuX upstream ships no local file and a blank base
	# identity, so this returns empties there and the caller falls back to env vars / prompt.
	param([string]$RepoRoot)

	$result = @{ Name = ""; Email = "" }
	$psDir = Join-Path -Path $RepoRoot -ChildPath "Windows\PowerShell"

	foreach ($file in @("Configuration.local.psd1", "Configuration.psd1")) {
		$path = Join-Path -Path $psDir -ChildPath $file
		if (-not (Test-Path -Path $path)) { continue }
		try {
			$data = Import-PowerShellDataFile -Path $path -ErrorAction Stop
		}
		catch { continue }
		if ([string]::IsNullOrWhiteSpace($result.Name) -and -not [string]::IsNullOrWhiteSpace($data.GitConfig.UserName)) {
			$result.Name = $data.GitConfig.UserName
		}
		if ([string]::IsNullOrWhiteSpace($result.Email) -and -not [string]::IsNullOrWhiteSpace($data.GitConfig.UserEmail)) {
			$result.Email = $data.GitConfig.UserEmail
		}
		if (-not [string]::IsNullOrWhiteSpace($result.Name) -and -not [string]::IsNullOrWhiteSpace($result.Email)) { break }
	}

	return $result
}

function Set-BootstrapGitIdentity {
	# Resolve the Git identity AFTER the repo is cloned and checked out, so a committed
	# Configuration.local.psd1 can supply it. Precedence: committed config -> WINUX_GIT_* env vars ->
	# identity already in the machine's global git config -> interactive prompt. If nothing resolves
	# in a non-interactive run, skip rather than writing a blank identity or hanging on a prompt.
	# Deferring identity to here (git clone/checkout need none) is what lets a fork provision a
	# brand-new machine with zero identity input.
	param([string]$RepoRoot)

	Write-Host -ForegroundColor DarkCyan "`n[Resolving Git Identity]`n"

	$fromConfig = Get-ConfiguredGitIdentity -RepoRoot $RepoRoot
	$gitName = $fromConfig.Name
	$gitEmail = $fromConfig.Email
	$source = "committed configuration"

	if ([string]::IsNullOrWhiteSpace($gitName) -and -not [string]::IsNullOrWhiteSpace($env:WINUX_GIT_NAME)) {
		$gitName = $env:WINUX_GIT_NAME
		$source = "WINUX_GIT_* environment variables"
	}
	if ([string]::IsNullOrWhiteSpace($gitEmail) -and -not [string]::IsNullOrWhiteSpace($env:WINUX_GIT_EMAIL)) {
		$gitEmail = $env:WINUX_GIT_EMAIL
	}

	if ([string]::IsNullOrWhiteSpace($gitName)) {
		$existingName = git config --global user.name 2>$null
		if (-not [string]::IsNullOrWhiteSpace($existingName)) { $gitName = $existingName; $source = "existing global git config" }
	}
	if ([string]::IsNullOrWhiteSpace($gitEmail)) {
		$existingEmail = git config --global user.email 2>$null
		if (-not [string]::IsNullOrWhiteSpace($existingEmail)) { $gitEmail = $existingEmail }
	}

	$interactive = [Environment]::UserInteractive
	if ([string]::IsNullOrWhiteSpace($gitName) -and $interactive) { $gitName = Read-Host -Prompt "  Git user.name"; $source = "prompt" }
	if ([string]::IsNullOrWhiteSpace($gitEmail) -and $interactive) { $gitEmail = Read-Host -Prompt "  Git user.email" }

	if ([string]::IsNullOrWhiteSpace($gitName) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
		Write-Host -ForegroundColor Yellow "   No Git identity resolved from config, WINUX_GIT_*, or git. Skipping global identity - set GitConfig in Configuration.local.psd1 (or WINUX_GIT_NAME / WINUX_GIT_EMAIL) to avoid a later commit failing."
		return
	}

	git config --global user.name "$gitName"
	git config --global user.email "$gitEmail"

	# Feed forward so the later Bootstrap -> Initialize-Configuration step (which reads these env vars)
	# stays consistent and never re-prompts.
	$env:WINUX_GIT_NAME = $gitName
	$env:WINUX_GIT_EMAIL = $gitEmail

	Write-Host -ForegroundColor DarkCyan "   user.name  => $gitName"
	Write-Host -ForegroundColor DarkCyan "   user.email => $gitEmail"
	Write-Host -ForegroundColor DarkCyan "   source     => $source"
}

function Initialize-Directory {
	param([string]$Path)
	if (-not (Test-Path $Path)) {
		New-Item -ItemType Directory -Path $Path -Force | Out-Null
		Write-Host -ForegroundColor Green "`n=> Created directory: $Path"
	}
}

function Get-RepositoryName {
	param([string]$RepositoryUrl)
	if ([string]::IsNullOrWhiteSpace($RepositoryUrl)) { return "" }
	try {
		$RepositoryUrl = $RepositoryUrl.TrimEnd('/')
		$RepositoryName = $RepositoryUrl -replace '^.*[:/]([^/:]+?)(\.git)?$', '$1'
		return $RepositoryName
	}
	catch { return "" }
}

function Initialize-Repository {
	param(
		[string]$RepositoryUrl,
		[string]$LocalPath,
		[string]$Token
	)
	$ParentPath = Split-Path -Path $LocalPath -Parent
	Initialize-Directory $ParentPath
	$RepositoryName = Get-RepositoryName -RepositoryUrl $RepositoryUrl

	if (-not (Test-Path $LocalPath)) {
		Write-Host -ForegroundColor DarkCyan "`n[Initializing [$RepositoryName] Repository]"

		if ([string]::IsNullOrWhiteSpace($Token)) {
			Write-Host -ForegroundColor DarkCyan "`n=> Cloning [$RepositoryName] to [$LocalPath] (public / anonymous)!"
			git clone $RepositoryUrl $LocalPath
		}
		else {
			# Trim stray whitespace from a pasted PAT and strip any existing token before
			# injecting, so a re-run or an already-authenticated URL never double-injects. Mirrors
			# the module Initialize-Repository.
			$CleanToken = $Token.Trim()
			$SanitizedUrl = $RepositoryUrl -replace 'https:\/\/.*@', 'https://'
			$AuthenticatedUrl = $SanitizedUrl.Replace("https://", "https://$($CleanToken)@")
			Write-Host -ForegroundColor DarkCyan "`n=> Cloning [$RepositoryName] to [$LocalPath] using authenticated URL!"
			git clone $AuthenticatedUrl $LocalPath

			# Never persist the token: git saves the clone URL verbatim as the origin remote
			# (.git/config, plaintext), where it would outlive the bootstrap and leak with any
			# `git remote -v`. Reset origin to the credential-free URL; future fetches
			# authenticate via the Git credential manager. Mirrors the module version.
			if (Test-Path (Join-Path $LocalPath ".git")) {
				git -C $LocalPath remote set-url origin $SanitizedUrl
				Write-Host -ForegroundColor DarkCyan "`n=> Token removed from the saved remote (credential manager handles future auth)!"
			}
		}

		try { takeown /f $LocalPath /r /d y | Out-Null } catch {}
	}
	else {
		Write-Host -ForegroundColor DarkCyan "`n[Updating [$RepositoryName] repository]"
		Write-Host -ForegroundColor Yellow "`n Repository [$RepositoryName] already exists at [$LocalPath]"
		Write-Host -ForegroundColor White "`nPulling latest changes..."
		Push-Location $LocalPath
		git pull
		Pop-Location
	}
}

function Install-Bootstrap {
	param(
		[Parameter(Mandatory = $false)]
		[string]$Branch = "master",
		[Parameter(Mandatory = $false)]
		[System.Security.SecureString]$Token
	)

	# Suppress progress bars to prevent console hanging
	$ProgressPreference = 'SilentlyContinue'

	if ($Token -and -not $global:GithubPat) {
		$global:GithubPat = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
			[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
		)
	}

	$isPS7 = $PSVersionTable.PSVersion.Major -ge 7

	if (-not $isPS7) {
		Install-PowerShell
		$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
		if (-not $pwshPath) {
			$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
			if (-not (Test-Path $pwshPath)) {
				Write-Host -ForegroundColor Red "PowerShell 7 installation failed or pwsh.exe not found. Install manually and try again!"
				Write-Host -ForegroundColor DarkCyan "Use this command => winget install Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements"
				return
			}
		}

		Start-PowerShell7WithAuth -PwshPath $pwshPath -TokenPlainText $global:GithubPat
	}

	Test-AdminPrivileges
	Start-Logging

	try {
		Write-Host -ForegroundColor DarkCyan "`n[First-Time Bootstrap Started]"

		Set-ExecutionPolicy Bypass -Scope Process -Force

		$config = Get-FirstRunConfiguration

		Install-Git

		$GithubFolderPath = $config.GithubPath
		$RepositoryUrl = $config.RepoUrl
		# Clone into a folder named after the repository itself: a 'WinuX' URL clones to
		# <GitHub>\WinuX, a personal fork named 'Dotfiles' clones to <GitHub>\Dotfiles. The repo
		# root is self-located at runtime ({RepoRoot}), so the folder name is free to match the
		# repo. Override with $env:WINUX_INSTALL_DIR to force a specific folder name.
		$RepositoryFolderName = if ($env:WINUX_INSTALL_DIR) { $env:WINUX_INSTALL_DIR } else { Get-RepositoryName -RepositoryUrl $RepositoryUrl }
		$RepoRoot = Join-Path $GithubFolderPath $RepositoryFolderName

		if ($Branch -ne "master") {
			Write-Host -ForegroundColor Yellow "`n=> Cloning from branch [$Branch]"
		}

		Initialize-Repository -RepositoryUrl $RepositoryUrl -LocalPath $RepoRoot -Token $global:GithubPat

		if ($Branch -ne "master") {
			Push-Location $RepoRoot
			Write-Host -ForegroundColor DarkCyan "`n=> Switching to branch [$Branch]"
			git checkout $Branch
			Pop-Location
		}

		# The repo (and its committed Configuration.local.psd1, if the fork ships one) is now on disk,
		# so resolve the global Git identity from it - falling back to WINUX_GIT_* env vars, the
		# machine's existing git config, or a prompt. This is what makes a committed-config fork
		# provision a brand-new machine with no identity prompt and no WINUX_GIT_* env vars.
		Set-BootstrapGitIdentity -RepoRoot $RepoRoot

		Write-Host -ForegroundColor DarkCyan "`n[Loading Full Bootstrap Module]"

		$BootstrapModulePath = Join-Path -Path $RepoRoot -ChildPath "Windows\PowerShell\Modules\Bootstrap"

		if (-not (Test-Path $BootstrapModulePath)) {
			throw "Bootstrap module not found after cloning! Expected at [$BootstrapModulePath]"
		}

		Remove-Module -Name Bootstrap -Force -ErrorAction SilentlyContinue

		try {
			$WarningPreference = "SilentlyContinue"
			Import-Module -Name $BootstrapModulePath -Force -Global
		}
		catch {
			Write-Host -ForegroundColor Red "`n=> Bootstrap module import failed => $($_.Exception.Message)"
		}

		Write-Host -ForegroundColor Green "`n=> Full module loaded! Handing over to the main Bootstrap function..."

		Bootstrap -RepoRoot $RepoRoot -WithInitialSetup
	}
	catch {
		Write-Host -ForegroundColor Red "`n=> Bootstrap failed => $($_.Exception.Message)"
		throw
	}
}

$branchParam = if ($env:WINUX_BRANCH) { $env:WINUX_BRANCH } else { "master" }

$bootstrapParams = @{
	Branch = $branchParam
}
if (Get-Variable -Name 'Token' -ErrorAction SilentlyContinue) {
	$bootstrapParams.Token = $Token
}

Install-Bootstrap @bootstrapParams
