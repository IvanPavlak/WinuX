function Load-PathConfiguration {
	<#
	.SYNOPSIS
		Loads Configuration.psd1, expands path placeholders, and registers modules for autoload.

	.DESCRIPTION
		Called automatically by the PowerShell profile on every shell start and by Bootstrap during
		provisioning. Not intended for direct invocation in normal use.

		Sets three global variables after a successful load:
		- `$global:Configuration`        - full Configuration.psd1 hashtable with Universal paths expanded
		- `$global:MachineType`          - detected machine type (PC, Laptop, Work, Test)
		- `$global:MachineSpecificPaths` - all PathTemplate paths expanded for the current machine

		Right after Configuration.local.psd1 is merged (WorkspaceTemplates template by template,
		everything else through Merge-Hashtable), Expand-WorkspaceTemplates turns every templated
		WorkspaceActions entry into a plain action list and substitutes {Workspace}, so no reader of
		WorkspaceActions has to know about templates.

		Environment variables such as %USERPROFILE% in the BasePaths values are expanded before
		the machine type is resolved and the paths are built.

		Also ensures the WinuX Modules directory is present in `$env:PSModulePath` so that all
		modules are available for autoloading, and registers the `Modules\Custom` fork area as an
		additional module root so whole fork-owned modules autoload the same way.

	.PARAMETER RepoRoot
		Absolute path to the WinuX repository root. Used to locate Configuration.psd1 at
		`Windows\PowerShell\Configuration.psd1` relative to this path.

	.PARAMETER Configuration
		An already-parsed Configuration.psd1 hashtable. When provided, skips reading the file from
		disk. Used by the profile to avoid parsing the file twice (Bootstrap reads it from disk).
		Configuration.local.psd1 is still merged into it.

	.PARAMETER Quiet
		Suppresses all console output. Used when loading configuration in background contexts.

	.EXAMPLE
		Load-PathConfiguration -RepoRoot "C:\Users\You\Development\GitHub\WinuX"
		Loads configuration from disk, sets global variables, and prints status output.

	.EXAMPLE
		Load-PathConfiguration -RepoRoot $path -Quiet
		Loads silently - no console output produced.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$RepoRoot,

		# Pass the already-loaded configuration to skip a second parse of Configuration.psd1.
		# If omitted the function reads the file from disk (e.g. when called from Bootstrap).
		[Parameter(Mandatory = $false)]
		[hashtable]$Configuration,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	if (-not $Quiet) {
		Write-LogTitle "Loading Path Configuration"
	}

	try {
		if ($Configuration) {
			$global:Configuration = $Configuration
		}
		else {
			$ConfigFile = Join-Path $RepoRoot "Windows\PowerShell\Configuration.psd1"

			if (-not (Test-Path $ConfigFile)) {
				if (-not $Quiet) {
					Write-LogError "Configuration file not found => [$ConfigFile]"
				}
				return $false
			}

			$global:Configuration = Import-PowerShellDataFile $ConfigFile

			if (-not $global:Configuration) {
				if (-not $Quiet) {
					Write-LogError "Configuration import returned null or empty!"
				}
				return $false
			}
		}

		# Deep-merge a personal Configuration.local.psd1 (if present) over the base config.
		# This keeps a fork's personal values (identity, machine paths, hostnames, ...) out of the
		# committed Configuration.psd1, so pulling upstream (WinuX) updates never conflicts on config.
		# Written by Initialize-Configuration; gitignored in WinuX. See OpenSource.md section 15.
		$LocalConfigFile = Join-Path $RepoRoot "Windows\PowerShell\Configuration.local.psd1"
		if (Test-Path $LocalConfigFile) {
			$localConfig = Import-PowerShellDataFile $LocalConfigFile
			if ($localConfig -is [hashtable]) {
				# The keys the local file sets, two levels deep (the depth the contract baseline
				# tracks), recorded before the merge folds them into the base. A runtime key, never a
				# setting: Test-ConfigurationSchema warns on the deprecated ones. The base keeps
				# shipping a deprecated key until the MAJOR that removes it, so only the local file
				# tells whether a fork still relies on one.
				$localConfigurationKeys = [System.Collections.Generic.List[string]]::new()
				foreach ($topKey in @($localConfig.Keys)) {
					$localConfigurationKeys.Add([string]$topKey)
					if ($localConfig[$topKey] -is [System.Collections.IDictionary]) {
						foreach ($childKey in @($localConfig[$topKey].Keys)) {
							$localConfigurationKeys.Add("$topKey.$childKey")
						}
					}
				}

				# WorkspaceTemplates merge template by template: a local template REPLACES the base
				# template of the same name instead of deep-merging into it (Merge-Hashtable would
				# keep the base template's Variables under a local Actions list).
				if ($localConfig.WorkspaceTemplates -is [hashtable] -and $global:Configuration.WorkspaceTemplates -is [hashtable]) {
					foreach ($templateName in @($localConfig.WorkspaceTemplates.Keys)) {
						$global:Configuration.WorkspaceTemplates[$templateName] = $localConfig.WorkspaceTemplates[$templateName]
					}
					$localConfig.Remove('WorkspaceTemplates')
				}
				Merge-Hashtable -Target $global:Configuration -Overrides $localConfig
				$global:Configuration['LocalConfigurationKeys'] = @($localConfigurationKeys)
				if (-not $Quiet) {
					Write-LogSuccess "Merged local overrides from Configuration.local.psd1"
				}
			}
		}

		# Expand environment variables (e.g. %USERPROFILE%) in BasePaths so a generic/template
		# config resolves to the real user instead of a hardcoded name. Literal absolute paths
		# contain no % tokens and are left unchanged, so personal forks are unaffected.
		if ($global:Configuration.BasePaths -is [hashtable]) {
			foreach ($mt in @($global:Configuration.BasePaths.Keys)) {
				$bp = $global:Configuration.BasePaths[$mt]
				if ($bp -is [hashtable]) {
					foreach ($pk in @($bp.Keys)) {
						if ($bp[$pk] -is [string]) { $bp[$pk] = [Environment]::ExpandEnvironmentVariables($bp[$pk]) }
					}
				}
			}
		}

		$Hostname = $env:COMPUTERNAME
		$global:MachineType = $global:Configuration.HostnameToMachineType[$Hostname]

		if (-not $global:MachineType) {
			if (-not $Quiet) {
				Write-LogWarning "Hostname [$Hostname] not in mapping! Using default => [$($global:Configuration.DefaultMachineType)]"
			}
			$global:MachineType = $global:Configuration.DefaultMachineType
		}

		if (-not $Quiet) {
			Write-LogSuccess "Detected Machine Type [$global:MachineType]"
		}

		# Ensure the WinuX modules folder is in PSModulePath so PowerShell can
		# autoload any module the first time one of its exported functions is called.
		$ModulesPath = Join-Path $RepoRoot "Windows\PowerShell\Modules"
		$CurrentModulePath = $env:PSModulePath -split ';'
		if ($CurrentModulePath -notcontains $ModulesPath) {
			$env:PSModulePath = $ModulesPath + ';' + $env:PSModulePath
			if (-not $Quiet) {
				Write-LogSuccess "Added modules path to PSModulePath"
			}
		}

		# The Custom area (Modules\Custom) can also host WHOLE fork-owned modules, each with its
		# own manifest and loader. Register it as an additional module root (after the engine
		# path) so those autoload exactly like engine modules; mirror payload folders carry no
		# manifest and are ignored by module discovery.
		$CustomPath = Join-Path $ModulesPath "Custom"
		if ((Test-Path $CustomPath) -and ($CurrentModulePath -notcontains $CustomPath)) {
			$env:PSModulePath = $env:PSModulePath + ';' + $CustomPath
		}

		# Workspace templates expand once, after the local merge, so every reader of
		# WorkspaceActions sees plain action lists (Expand-WorkspaceTemplates keeps the raw
		# templated definitions under WorkspaceTemplateEntries for Open-Workspace and
		# Test-ConfigurationSchema). A broken template is reported, never fatal to the load.
		try {
			$null = Expand-WorkspaceTemplates -Configuration $global:Configuration -Quiet:$Quiet
		}
		catch {
			if (-not $Quiet) {
				Write-LogWarning "Workspace templates were not expanded: $($_.Exception.Message)"
			}
		}

		# Expand path placeholders - triggers autoload of the Helper module on first call.
		$basePath = $global:Configuration.BasePaths[$global:MachineType].Dev
		$userPath = $global:Configuration.BasePaths[$global:MachineType].User
		$global:Configuration.Universal = Expand-Hashtable -Source $global:Configuration.Universal -DevPath $basePath -UserPath $userPath -MachineTypeName $global:MachineType -RepoRoot $RepoRoot
		$global:Configuration.Universal.Desktop = [Environment]::GetFolderPath("Desktop")
		$global:MachineSpecificPaths = Expand-ConfigPaths -Configuration $global:Configuration -MachineType $global:MachineType -RepoRoot $RepoRoot

		if (-not $Quiet) {
			Write-LogSuccess "Path configuration loaded successfully!"
		}
		return $true
	}
	catch {
		if (-not $Quiet) {
			Write-LogError "Failed to load path configuration: $_" -Exception $_
		}
		return $false
	}
}
