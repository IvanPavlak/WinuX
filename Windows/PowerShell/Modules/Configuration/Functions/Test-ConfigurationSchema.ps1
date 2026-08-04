function Test-ConfigurationSchema {
	<#
	.SYNOPSIS
		Validates that all required keys are present in the loaded configuration.

	.DESCRIPTION
		Checks the global $Configuration hashtable for the presence and non-null/non-empty
		values of every key required by core module functions. Reports all missing or empty
		keys as warnings. Does not throw - missing keys produce warnings so the shell can
		still start with a degraded configuration rather than failing entirely.

		Only FRAMEWORK keys are required. User-specific sections (themes, wallpapers,
		locale, keyboard layouts, Wake-on-LAN, taskbar pins, ...) ship empty by design
		and their consumers no-op with a warning, so an untouched vanilla configuration
		is valid. The exception is GitConfig.UserName/UserEmail, which the base ships
		blank and Initialize-Configuration fills into Configuration.local.psd1 on the
		first run - they warn until then.

		Call this function immediately after Load-PathConfiguration during the bootstrap
		or profile initialization sequence to surface typos and missing entries early.

	.PARAMETER Configuration
		The configuration hashtable to validate. Defaults to $global:Configuration.

	.PARAMETER Strict
		If specified, throws a terminating error when any required key is missing.
		Use during bootstrap/testing; omit for profile startup (warning-only).

	.EXAMPLE
		Test-ConfigurationSchema
		Validates $global:Configuration and writes a warning for each missing key.

	.EXAMPLE
		Test-ConfigurationSchema -Strict
		Throws if any required key is absent (suitable for bootstrap validation).

	.EXAMPLE
		Test-ConfigurationSchema -Configuration $myConfig
		Validates a specific configuration hashtable rather than the global one.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[switch]$Strict
	)

	$failures = [System.Collections.Generic.List[string]]::new()

	if ($null -eq $Configuration) {
		$msg = "Configuration is null - Load-PathConfiguration may not have run."
		if ($Strict) { throw $msg } else { Write-Warning $msg ; return }
	}

	# Required top-level keys and nested paths: [description, key-path-array]
	#
	# Only FRAMEWORK keys belong here - the ones the engine cannot resolve paths or
	# detect a machine without. Everything user-specific ships empty by design (see the
	# empty-by-default philosophy in Configuration.psd1) and its consumer no-ops with a
	# warning, so requiring it here would flag a correct vanilla install as broken.
	$requiredKeys = @(
		# Machine detection
		@{ Desc = "ValidMachineTypes"; Path = @('ValidMachineTypes') }
		@{ Desc = "HostnameToMachineType"; Path = @('HostnameToMachineType') }
		@{ Desc = "DefaultMachineType"; Path = @('DefaultMachineType') }
		@{ Desc = "LaptopChassisTypes"; Path = @('LaptopChassisTypes') }

		# Path system
		@{ Desc = "BasePaths"; Path = @('BasePaths') }
		@{ Desc = "PathTemplates"; Path = @('PathTemplates') }
		@{ Desc = "Projects.Self.Root"; Path = @('PathTemplates', 'Projects', 'Self', 'Root') }

		# Git
		@{ Desc = "GitConfig.UserName"; Path = @('GitConfig', 'UserName') }
		@{ Desc = "GitConfig.UserEmail"; Path = @('GitConfig', 'UserEmail') }
		@{ Desc = "GitConfig.WingetPackageId"; Path = @('GitConfig', 'WingetPackageId') }

		# Locale, keyboard layouts and display language are NOT required: they ship
		# empty and Set-Locale / Set-KeyboardLayouts / Set-DisplayLanguage leave the
		# system as-is until a fork opts in via Configuration.local.psd1.

		# Application paths
		@{ Desc = "BrowserGroups"; Path = @('BrowserGroups') }
		@{ Desc = "PathTemplates.SymbolicLinks"; Path = @('PathTemplates', 'SymbolicLinks') }
		@{ Desc = "RepositoryGroups"; Path = @('RepositoryGroups') }
	)

	foreach ($entry in $requiredKeys) {
		if (-not (Test-ConfigurationKeyPath -Table $Configuration -Path $entry.Path)) {
			$failures.Add("Missing or empty required key: $($entry.Desc)")
		}
	}

	if ($failures.Count -gt 0) {
		$summary = "Configuration schema validation found $($failures.Count) issue(s):"
		$detail = $failures -join "`n  - "
		$message = "$summary`n  - $detail`n`nVerify Configuration.psd1 and that Load-PathConfiguration completed successfully."

		if ($Strict) {
			throw $message
		}
		else {
			Write-Warning $message
		}
	}
	else {
		Write-Verbose "Configuration schema validation passed - all required keys present."
	}
}
