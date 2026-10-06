# | ------------------------------ < Minimal Bootstrap > ------------------------------ | #

# The configuration file (parsed below, inside the Core stage, and passed to Load-PathConfiguration
# to avoid a second parse)
$ConfigFile = Join-Path $PSScriptRoot "Configuration.psd1"
if (-not (Test-Path -Path $ConfigFile)) {
	Write-Host -ForegroundColor Red "`n=> Configuration file not found: $ConfigFile"
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

# Every startup stage below is wrapped in a guard pair so it can be timed and, for one shell start,
# left out: `if (Test-StartupStage X) { ...; Complete-StartupStage }`. WINUX_STARTUP_SKIP names the
# stages to skip (or All), WINUX_STARTUP_TRACE a file the per-stage times are appended to, and
# $WinuXStartupTimings holds them for the running shell. Measure-ShellStartup drives both to build
# the strip-everything-then-add-one-stage-at-a-time table. Dot-sourced like Get-RepositoryPath
# because no module is imported yet. Core - the configuration parse and the imports everything else
# reads - is Required: it runs whatever the skip list says, but is still timed.
#
# Get-ConfigSetting and Test-ConfigValue ride along for a different reason: they are the only two
# Helper functions anything before the first prompt calls, and calling either through autoload would
# import the whole Helper module (80+ files, measured at 330-500 ms) plus PowerShell's module
# discovery on top. Dot-sourced, the shell reaches its prompt without importing Helper at all; the
# first Helper command typed afterwards autoloads the module as before, and the module's copies
# simply replace these.
foreach ($stageFunction in "Test-StartupStage", "Complete-StartupStage", "Get-ConfigSetting", "Test-ConfigValue") {
	. (Join-Path $ModulesPath "Helper\Functions\$stageFunction.ps1")
}
$null = Test-StartupStage -Name "Core" -Required

try {
	$global:Configuration = Import-PowerShellDataFile -Path $ConfigFile
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to load Configuration file => $_"
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
Complete-StartupStage

# Validate the loaded configuration against the required-key schema (warning-only, so a degraded
# config still starts the shell). -WarningAction Continue surfaces issues even though startup
# warnings are muted during the Bootstrap import above. Dot-sourced with its one helper so the
# check does not autoload the Configuration module before the prompt.
if (Test-StartupStage -Name "Schema") {
	foreach ($schemaFunction in "Test-ConfigurationKeyPath", "Test-ConfigurationSchema") {
		. (Join-Path $ModulesPath "Configuration\Functions\$schemaFunction.ps1")
	}
	Test-ConfigurationSchema -WarningAction Continue
	Complete-StartupStage
}

# | ------------------------------ < Enhance Console Experience > ------------------------------ | #

# The terminal greeting: clear, the fastfetch system info panel, and - inside a git repository, when
# TerminalGreeting.Onefetch.Enabled is on - the onefetch repository panel. Each step skips itself
# silently when its binary is not installed yet, so a freshly cloned machine starts without an error
# at the prompt.
#
# -NoResize skips the font auto-fit: a fresh shell has nothing on screen to redraw, and the Ctrl+0 /
# Ctrl+Minus round trips would only delay the first prompt. `c` (Show-TerminalGreeting) does fit.
#
# Dot-sourced like Initialize-PSReadLine below, because this runs before the System and Git modules
# are imported. Ten files: the orchestrator, its three steps, the settings resolver, the onefetch
# restyler the all-hosts profile's wrapper calls, the three the all-hosts profile's fastfetch
# wrapper calls for the image logo (which would otherwise autoload the whole System module - 80+
# files, 350-500 ms - before the first prompt), and the repository test the onefetch step is gated
# on.
if (Test-StartupStage -Name "Greeting") {
	foreach ($greetingFunction in "Resolve-TerminalGreetingSettings", "Invoke-Clear", "Invoke-Fastfetch", "Invoke-Onefetch", "Format-OnefetchPanel", "Show-TerminalGreeting", "Get-FastfetchLogoArgument", "Get-TerminalCellSize", "New-SixelImage") {
		. (Join-Path $ModulesPath "System\Functions\$greetingFunction.ps1")
	}
	. (Join-Path $ModulesPath "Git\Functions\Test-GitRepository.ps1")
	Show-TerminalGreeting -NoResize
	Complete-StartupStage
}

# Import the PSReadLine module for enhanced command-line features if we're in the console host
if (Test-StartupStage -Name "PSReadLine") {
	if ($host.Name -eq "ConsoleHost") {
		Import-Module PSReadLine
	}
	Complete-StartupStage
}

# Spectre.Console - Configuring the Windows Terminal For Unicode and Emoji Support
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Work that has to happen in this session but not before the first prompt is queued here and run by
# the single PowerShell.OnIdle subscription registered at the end of this file, which fires once the
# prompt is rendered and the shell has been idle ~300 ms. Each entry is a scriptblock; the
# subscription runs them in order, each in its own try/catch, so one failing never stops the next.
$deferredStartup = [System.Collections.Generic.List[scriptblock]]::new()

# Import the Terminal-Icons module (if installed) for displaying icons in the console. Deferred:
# the import was measured at 165-400 ms and the icons are only needed once something is listed, so
# it runs after the prompt - -Global, because the OnIdle action is a scope of its own. The one
# observable difference is a listing typed within the first ~300 ms of a new shell, which prints
# without icons; every later one has them.
if (Test-StartupStage -Name "Terminal-Icons") {
	$deferredStartup.Add({
			if (Get-Module -ListAvailable -Name Terminal-Icons) {
				Import-Module -Name Terminal-Icons -Global
			}
		})
	Complete-StartupStage
}

# PSReadLine interactive options (edit mode, key handlers, history limits, predictions) come from
# Configuration.PSReadLine and are applied by Initialize-PSReadLine, which owns the ordering rules
# (-EditMode first, since it resets every earlier binding; the prediction options last and guarded,
# since they throw on consoles without virtual-terminal support). Forks tune them in
# Configuration.local.psd1, not here. Dot-sourced like Initialize-OhMyPosh below so it is available
# before the System module is imported.
if (Test-StartupStage -Name "PSReadLineOptions") {
	. (Join-Path $ModulesPath "System\Functions\Initialize-PSReadLine.ps1")
	Initialize-PSReadLine
	Complete-StartupStage
}

# Oh-My-Posh - binary resolution + init live in Initialize-OhMyPosh. Dot-invoked so the
# prompt it defines lands in this scope. On provisioned machines (AutoPathAdditions puts
# the install locations on the User PATH) this is effectively the classic one-liner.
#
# MUST stay below the PSReadLine block. A theme carrying a `transient_prompt` object makes the
# init script bind Enter to OhMyPoshEnterKeyHandler; an -EditMode call after it resets Enter to
# AcceptLine and the transient prompt then silently never fires.
if (Test-StartupStage -Name "OhMyPosh") {
	. (Join-Path $ModulesPath "System\Functions\Initialize-OhMyPosh.ps1")
	. Initialize-OhMyPosh
	Complete-StartupStage
}

# | ------------------------------ < Aliases > ------------------------------ | #

if (Test-StartupStage -Name "Aliases") {

	# | --------------- < Git Aliases > --------------- | #

	New-Alias -Name gb -Value GitBranch -Force -Option AllScope

	New-Alias -Name gbd -Value GitBranchDeleteAndPrune -Force -Option AllScope

	New-Alias -Name gsw -Value GitSwitch -Force -Option AllScope

	New-Alias -Name gp -Value GitPull -Force -Option AllScope

	New-Alias -Name gmm -Value GitMergeM -Force -Option AllScope

	New-Alias -Name gs -Value GitStatus -Force -Option AllScope

	# | --------------- < Miscellaneous Aliases > --------------- | #

	New-Alias -Name w -Value Open-Workspace -Force

	New-Alias -Name cw -Value Close-Workspace -Force

	New-Alias -Name c -Value Show-TerminalGreeting -Force

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

	Complete-StartupStage
}

# | ------------------------------ < Startup Checks > ------------------------------ | #

if (Test-StartupStage -Name "PowerPlan") {
	foreach ($powerPlanFunction in "Get-ChassisType", "Test-PowerPlan") {
		. (Join-Path $ModulesPath "System\Functions\$powerPlanFunction.ps1")
	}
	Test-PowerPlan
	Complete-StartupStage
}

# Background log maintenance - prunes session logs and stale test-run artifacts at most once per
# Configuration.Logging.Maintenance.IntervalHours. Deferred like Terminal-Icons above. On
# already-swept days the fired action hits the stamp-file check inside Invoke-LogMaintenance and
# returns in ~1ms.
if (Test-StartupStage -Name "LogMaintenance") {
	$deferredStartup.Add({ Invoke-LogMaintenance })
	Complete-StartupStage
}

# Automatic repository update - pulls the configured repositories at most once per
# Configuration.RepositoryUpdate.Startup.IntervalHours, off unless Startup.Enabled is $true. Deferred
# like LogMaintenance, and queued after it, so the prompt is already drawn when it runs; its compact
# summary prints below the prompt, typing waits until the fetches finish, and -RedrawPrompt draws
# the prompt again under the summary (without it PSReadLine waits on a blank line). Disabled or
# inside the interval, the fired action returns in about a millisecond and redraws nothing.
if (Test-StartupStage -Name "RepositoryUpdate") {
	$deferredStartup.Add({ Invoke-StartupRepositoryUpdate -RedrawPrompt })
	Complete-StartupStage
}

# The one PowerShell.OnIdle subscription that runs the deferred work. Registering the engine event
# costs well under a millisecond, and the action fires only AFTER the prompt is rendered and the
# shell has been idle ~300ms - so shell launch pays nothing. The queue travels as a global variable
# because the action runs in a scope of its own - NOT as -MessageData: Register-EngineEvent with
# -Action silently drops it ($Event.MessageData arrives $null), so the loop would run over nothing
# and every deferred entry would quietly never happen. The action's pipeline output goes to the
# event system, never the console, and it unregisters itself so it fires at most once per session;
# -SupportEvent keeps the subscription and its event job out of Get-Job / Get-EventSubscriber
# (which is also why unregistering needs -Force).
if ($deferredStartup.Count -gt 0) {
	$global:WinuXDeferredStartup = $deferredStartup
	Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
		foreach ($deferredAction in $global:WinuXDeferredStartup) {
			try { & $deferredAction } catch { }
		}
		Remove-Variable -Name WinuXDeferredStartup -Scope Global -ErrorAction SilentlyContinue
		Unregister-Event -SourceIdentifier PowerShell.OnIdle -Force -ErrorAction SilentlyContinue
	}
}

# Integrity checks are intentionally NOT run at startup (they add ~200ms+ and shell launch
# must stay fast). Run them on-demand instead:
#   List-Functions -ListDiscrepancies   - functions loaded vs documented in docs/modules
#   Test-ManifestCompleteness           - function files on disk vs each module's FunctionsToExport
#   Run-Tests -TestName "Infrastructure" - the hermetic CI versions of both, plus documentation
#                                          links and the per-function configuration guides
