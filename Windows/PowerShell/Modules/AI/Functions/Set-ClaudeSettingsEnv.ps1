function Set-ClaudeSettingsEnv {
	<#
	.SYNOPSIS
		Sets one variable in the env block of a Claude Code settings.json, preserving every other key.

	.DESCRIPTION
		Claude Code reads environment variables for itself from the `env` object of its user
		settings file (~\.claude\settings.json). That file belongs to the user and to Claude Code,
		which rewrites it as settings change, so this function never replaces it: it reads the
		whole document, sets exactly one key under `env`, and writes the whole document back, so
		every other top-level key, every nested object (permissions, hooks, ...) and every other
		`env` variable survives.

		  - Missing file: the directory is created and the file is written as
		    { "env": { "<Name>": "<Value>" } }.
		  - File without an `env` object: one is added.
		  - Value already set: nothing is written.
		  - Unparseable JSON, a top level that is not an object, or an `env` that is not an
		    object: an error is logged, the file is left untouched, and $false is returned.

		The file is written as UTF-8 without a BOM, two-space indented with LF line endings (the
		shape Claude Code writes). Date-like strings are read as strings so they round-trip
		unchanged.

		Returns $true when the file holds (or, under -WhatIf, would hold) the value afterwards,
		$false when the file could not be changed.

	.PARAMETER Name
		The environment variable to set under `env`, e.g. CLAUDE_CODE_PLUGIN_DIRS.

	.PARAMETER Value
		The value to store. An empty string is stored as an empty string.

	.PARAMETER SettingsPath
		The settings file to edit. Defaults to ~\.claude\settings.json. Accepts a \\wsl.localhost
		path to edit a WSL user's settings from Windows.

	.EXAMPLE
		Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "C:\Users\You\.claude\mods\my-mod"
		Points Claude Code at one plugin folder, keeping every other setting.

	.EXAMPLE
		Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "" -WhatIf
		Reports the change without writing.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[string]$Value,

		[Parameter()]
		[string]$SettingsPath = (Join-Path $env:USERPROFILE ".claude\settings.json")
	)

	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

	if (-not (Test-Path -LiteralPath $SettingsPath)) {
		if ($PSCmdlet.ShouldProcess($SettingsPath, "Create with env.$Name")) {
			New-Item -ItemType Directory -Path (Split-Path -Parent $SettingsPath) -Force | Out-Null
			$document = [ordered]@{ env = [ordered]@{ $Name = $Value } }
			$json = ($document | ConvertTo-Json -Depth 32) -replace "`r`n", "`n"
			[IO.File]::WriteAllText($SettingsPath, $json + "`n", $utf8NoBom)
			Write-LogStep "Created [$SettingsPath] with env.$Name"
		}
		return $true
	}

	# PowerShell 7.5+ would otherwise turn ISO date strings into DateTime and write them back reformatted.
	$jsonParams = @{ ErrorAction = 'Stop' }
	if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
		$jsonParams.DateKind = 'String'
	}

	try {
		$raw = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop
		$settings = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json @jsonParams }
	}
	catch {
		Write-LogError "Could not parse [$SettingsPath] - left untouched => $($_.Exception.Message)"
		return $false
	}

	if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
		Write-LogError "The top level of [$SettingsPath] is not a JSON object - left untouched!"
		return $false
	}

	$envProperty = $settings.PSObject.Properties['env']
	if ($null -eq $envProperty -or $null -eq $envProperty.Value) {
		$settings | Add-Member -MemberType NoteProperty -Name 'env' -Value ([pscustomobject]@{}) -Force
	}
	elseif ($envProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
		Write-LogError "The env entry in [$SettingsPath] is not a JSON object - left untouched!"
		return $false
	}

	$current = $settings.env.PSObject.Properties[$Name]
	if ($null -ne $current -and [string]$current.Value -ceq $Value -and $current.Value -is [string]) {
		Write-LogStep "env.$Name in [$SettingsPath] is already up to date"
		return $true
	}

	$settings.env | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force

	if ($PSCmdlet.ShouldProcess($SettingsPath, "Set env.$Name")) {
		$json = ($settings | ConvertTo-Json -Depth 32) -replace "`r`n", "`n"
		[IO.File]::WriteAllText($SettingsPath, $json + "`n", $utf8NoBom)
		Write-LogStep "Set env.$Name in [$SettingsPath]"
	}
	return $true
}
