function Set-ClaudeSettingsKey {
	<#
	.SYNOPSIS
		Sets one key, at any depth, of a Claude Code settings.json, preserving every other key.

	.DESCRIPTION
		Claude Code keeps more than environment variables in its user settings file
		(~\.claude\settings.json): the marketplaces it knows (`extraKnownMarketplaces`), the
		plugins it enables (`enabledPlugins`), each plugin's options (`pluginConfigs`), and so on.
		That file belongs to the user and to Claude Code, which rewrites it as settings change,
		so this function never replaces it: it reads the whole document, sets exactly one key
		named by a dotted path, and writes the whole document back, so every other top-level key,
		every nested object and every sibling survives. Set-ClaudeSettingsEnv is the same
		operation fixed to the `env` block; this one reaches any key.

		  - Missing file: the directory is created and the file is written with only the path.
		  - Missing objects along the path: created.
		  - Value already equal (compared as JSON): nothing is written.
		  - Unparseable JSON, a top level that is not an object, or a value along the path that
		    exists but is not an object: an error is logged, the file is left untouched, and
		    $false is returned.

		A hashtable or array value is stored as the JSON object or array it describes; a string,
		number or boolean as itself. The file is written as UTF-8 without a BOM, two-space
		indented with LF line endings (the shape Claude Code writes). Date-like strings are read
		as strings so they round-trip unchanged.

		Returns $true when the file holds (or, under -WhatIf, would hold) the value afterwards,
		$false when the file could not be changed.

	.PARAMETER Path
		The key to set, as a dotted path from the top level, e.g. extraKnownMarketplaces.my-marketplace
		or pluginConfigs.my-plugin.options. A segment may not be empty.

	.PARAMETER Value
		The value to store: a string, number, boolean, hashtable (JSON object) or array.

	.PARAMETER SettingsPath
		The settings file to edit. Defaults to ~\.claude\settings.json. Accepts a \\wsl.localhost
		path to edit a WSL user's settings from Windows.

	.EXAMPLE
		Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.my-marketplace" -Value @{ source = @{ source = "github"; repo = "MyOrg/MyMarketplace" } }
		Registers a marketplace Claude Code adds on its next start, keeping every other setting.

	.EXAMPLE
		Set-ClaudeSettingsKey -Path "pluginConfigs.my-plugin.options" -Value @{ theme = "light" } -WhatIf
		Reports the change without writing.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[AllowEmptyString()]
		[object]$Value,

		[Parameter()]
		[string]$SettingsPath = (Join-Path $env:USERPROFILE ".claude\settings.json")
	)

	$segments = @($Path.Split('.'))
	if (@($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
		Write-LogError "Invalid settings path [$Path] - every segment must be non-empty!"
		return $false
	}

	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

	# PowerShell 7.5+ would otherwise turn ISO date strings into DateTime and write them back reformatted.
	$jsonParams = @{ ErrorAction = 'Stop' }
	if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
		$jsonParams.DateKind = 'String'
	}

	# Hashtables and arrays become the JSON they describe; the round trip gives the same object
	# shape ConvertFrom-Json yields for the file, so the comparison below is like with like.
	$normalized = $Value
	if ($Value -is [System.Collections.IDictionary] -or ($Value -is [array])) {
		$normalized = ($Value | ConvertTo-Json -Depth 32) | ConvertFrom-Json @jsonParams
	}
	# Equality ignores key order: a hashtable's order and the file's rarely agree.
	function script:ConvertTo-CanonicalValue($v) {
		if ($v -is [System.Management.Automation.PSCustomObject]) {
			$sorted = [ordered]@{}
			foreach ($prop in ($v.PSObject.Properties | Sort-Object Name)) { $sorted[$prop.Name] = ConvertTo-CanonicalValue $prop.Value }
			return $sorted
		}
		if ($v -is [array]) { return @($v | ForEach-Object { , (ConvertTo-CanonicalValue $_) }) }
		return $v
	}
	$asJson = { param($v) if ($null -eq $v) { 'null' } else { ConvertTo-CanonicalValue $v | ConvertTo-Json -Depth 32 -Compress } }

	if (-not (Test-Path -LiteralPath $SettingsPath)) {
		if ($PSCmdlet.ShouldProcess($SettingsPath, "Create with $Path")) {
			New-Item -ItemType Directory -Path (Split-Path -Parent $SettingsPath) -Force | Out-Null
			$leaf = $normalized
			for ($i = $segments.Count - 1; $i -ge 0; $i--) {
				$leaf = [ordered]@{ $segments[$i] = $leaf }
			}
			$json = ($leaf | ConvertTo-Json -Depth 32) -replace "`r`n", "`n"
			[IO.File]::WriteAllText($SettingsPath, $json + "`n", $utf8NoBom)
			Write-LogStep "Created [$SettingsPath] with $Path"
		}
		return $true
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

	# Walk to the parent of the leaf, creating objects where the path has none.
	$parent = $settings
	$walked = @()
	for ($i = 0; $i -lt $segments.Count - 1; $i++) {
		$name = $segments[$i]
		$walked += $name
		$property = $parent.PSObject.Properties[$name]
		if ($null -eq $property -or $null -eq $property.Value) {
			$parent | Add-Member -MemberType NoteProperty -Name $name -Value ([pscustomobject]@{}) -Force
		}
		elseif ($property.Value -isnot [System.Management.Automation.PSCustomObject]) {
			Write-LogError "The entry [$($walked -join '.')] in [$SettingsPath] is not a JSON object - left untouched!"
			return $false
		}
		$parent = $parent.$name
	}

	$leafName = $segments[-1]
	$current = $parent.PSObject.Properties[$leafName]
	if ($null -ne $current -and (& $asJson $current.Value) -ceq (& $asJson $normalized)) {
		Write-LogStep "$Path in [$SettingsPath] is already up to date"
		return $true
	}

	$parent | Add-Member -MemberType NoteProperty -Name $leafName -Value $normalized -Force

	if ($PSCmdlet.ShouldProcess($SettingsPath, "Set $Path")) {
		$json = ($settings | ConvertTo-Json -Depth 32) -replace "`r`n", "`n"
		[IO.File]::WriteAllText($SettingsPath, $json + "`n", $utf8NoBom)
		Write-LogStep "Set $Path in [$SettingsPath]"
	}
	return $true
}
