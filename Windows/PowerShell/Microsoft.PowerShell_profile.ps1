# | ------------------------------ < Minimal Bootstrap > ------------------------------ | #

# Load configuration (passed to Load-PathConfiguration below to avoid a second parse)
$ConfigFile = Join-Path $PSScriptRoot "Configuration.psd1"
if (-not (Test-Path -Path $ConfigFile)) {
	Write-Host -ForegroundColor Red "`n=> Configuration file not found: $ConfigFile"
	return
}

try {
	$global:Configuration = Import-PowerShellDataFile -Path $ConfigFile
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to load Configuration file => $_"
	return
}

# Resolve this repo from the profile's own Configuration.psd1. On a provisioned machine the profile
# and Configuration.psd1 are symlinked beside each other inside the repo, so resolving the config to
# its real on-disk path locates the repo (and its Modules) no matter where it was cloned or what the
# root folder is named - nothing is hardcoded. Load-PathConfiguration (below) then performs the
# machine-type detection and the Configuration.local.psd1 deep-merge for the full configuration.
$ConfigItem = Get-Item -LiteralPath $ConfigFile -Force
$RealConfigFile = if ($ConfigItem.Target) { @($ConfigItem.Target)[0] } else { $ConfigFile }

# Derive every repo path from the config's real location via the shared Get-RepositoryPath helper.
# The profile runs before any module is imported, so dot-source the helper's single dependency-free
# file directly rather than relying on module autoload. -StartPath anchors the walk on the resolved
# PowerShell dir, so nothing here counts folder levels by hand.
$PowerShellDir = Split-Path -Path $RealConfigFile -Parent
. (Join-Path $PowerShellDir "Modules\Helper\Functions\Get-RepositoryPath.ps1")
$RepoPaths = Get-RepositoryPath -StartPath $PowerShellDir
$ModulesPath = $RepoPaths.Modules
$RepoRoot = $RepoPaths.Repo

if (-not (Test-Path $ModulesPath)) {
	Write-Host -ForegroundColor Red "`n=> Modules path not found [$ModulesPath]"
	return
}

$CurrentModulePath = $env:PSModulePath -split ';'
if ($CurrentModulePath -notcontains $ModulesPath) {
	$env:PSModulePath = $ModulesPath + ';' + $env:PSModulePath
}

# Import the Logging module first so every module (including Bootstrap's Start-Logging /
# Stop-Logging and all Write-Log* output) can use unified logging from the very start.
try {
	Import-Module -Name Logging -Force -ErrorAction Stop -Global | Out-Null
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to import Logging module => $_"
}

# Import Bootstrap module only
try {
	$WarningPreference = "SilentlyContinue"
	Import-Module -Name Bootstrap -Force -ErrorAction Stop -Global | Out-Null
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to import Bootstrap module => $_"
	return
}

# Let Bootstrap handle the rest (configuration, paths, module imports)
if (-not (Load-PathConfiguration -RepoRoot $RepoRoot -Configuration $global:Configuration -Quiet)) {
	Write-Host -ForegroundColor Red "`n=> Failed to load path configuration!"
	return
}

# Validate the loaded configuration against the required-key schema (warning-only, so a degraded
# config still starts the shell). -WarningAction Continue surfaces issues even though startup
# warnings are muted during the Bootstrap import above.
Test-ConfigurationSchema -WarningAction Continue

# Import the fork-owned Custom module so fork-local functions (Modules\Custom - see the Fork
# Model docs) are available immediately; its wildcard manifest cannot participate in autoload.
# On a pure-upstream setup the Custom area ships empty, so this is effectively a no-op.
try {
	Import-Module -Name Custom -Force -ErrorAction Stop -Global | Out-Null
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to import Custom module => $_"
}

# | ------------------------------ < Enhance Console Experience > ------------------------------ | #

# Oh-My-Posh - binary resolution + init live in Initialize-OhMyPosh. Dot-invoked so the
# prompt it defines lands in this scope. On provisioned machines (AutoPathAdditions puts
# the install locations on the User PATH) this is effectively the classic one-liner.
. (Join-Path $ModulesPath "System\Functions\Initialize-OhMyPosh.ps1")
. Initialize-OhMyPosh

# Display system information (skip silently when fastfetch is not installed yet)
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
	fastfetch
}

# Import the PSReadLine module for enhanced command-line features if we're in the console host
if ($host.Name -eq "ConsoleHost") {
	Import-Module PSReadLine
}

# Spectre.Console - Configuring the Windows Terminal For Unicode and Emoji Support
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import the Terminal-Icons module (if installed) for displaying icons in the console
if (Get-Module -ListAvailable -Name Terminal-Icons) {
	Import-Module -Name Terminal-Icons
}

# PSReadLine interactive options. Guarded: the prediction options throw in consoles without
# virtual-terminal support (redirected output, CI, automation hosts) - a cosmetic feature must
# never break shell startup there.
try {
	# Set the Up/Down Arrow keys to search through command history
	Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
	Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

	# Set the command suggestion source to be the command history
	Set-PSReadLineOption -PredictionSource History

	# Set the command suggestion display style to a list view
	Set-PSReadLineOption -PredictionViewStyle ListView

	# Set the editing mode to Windows (Ctrl+C to copy, Ctrl+V to paste, etc.)
	Set-PSReadLineOption -EditMode Windows
}
catch {
	# Non-interactive/limited console - keep defaults silently.
}

# | ------------------------------ < Aliases > ------------------------------ | #

# | --------------- < Git Aliases > --------------- | #

New-Alias -Name gb -Value GitBranch -Force -Option AllScope

New-Alias -Name gbd -Value GitBranchDeleteAndPrune -Force -Option AllScope

New-Alias -Name gsw -Value GitSwitch -Force -Option AllScope

New-Alias -Name gp -Value GitPull -Force -Option AllScope

New-Alias -Name gmm -Value GitMergeM -Force -Option AllScope

New-Alias -Name gs -Value GitStatus -Force -Option AllScope

# | --------------- < Miscellaneous Aliases > --------------- | #

New-Alias -Name w -Value Open-Workspace -Force

New-Alias -Name c -Value Invoke-ClearAndFastfetch -Force

New-Alias -Name l -Value ls -Force

New-Alias -Name dnr -Value DotnetRun -Force -Option AllScope

New-Alias -Name dnbr -Value DotnetBuildAndRun -Force -Option AllScope

New-Alias -Name dnp -Value DotnetPublish -Force -Option AllScope

New-Alias -Name nir -Value NpmInstallAndStart -Force -Option AllScope

New-Alias -Name efm -Value EfCoreMigrationWizard -Force -Option AllScope

New-Alias -Name rp -Value Run-Project -Force -Option AllScope

New-Alias -Name t -Value Open-Terminal -Force

New-Alias -Name gdf -Value Git-Diff -Force

New-Alias -Name b -Value Invoke-Browser -Force

New-Alias -Name translate -Value Invoke-GoogleTranslate -Force

# | ------------------------------ < Startup Checks > ------------------------------ | #

. (Join-Path $ModulesPath "System\Functions\Test-PowerPlan.ps1")
Test-PowerPlan

# Integrity checks are intentionally NOT run at startup (they add ~200ms+ and shell launch
# must stay fast). Run them on-demand instead:
#   List-Functions -ListDiscrepancies   - functions loaded vs documented in docs/modules
#   Test-ManifestCompleteness           - function files on disk vs each module's FunctionsToExport
