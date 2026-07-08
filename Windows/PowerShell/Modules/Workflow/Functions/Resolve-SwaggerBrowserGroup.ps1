function Resolve-SwaggerBrowserGroup {
	<#
	.SYNOPSIS
		Resolves the Swagger browser group for a project, ready to hand to Open-Browser.

	.DESCRIPTION
		Maps a project name to its entry in the BrowserGroups "Swagger" group (case-insensitive
		match on the entry's Name) and returns that group name so the caller can add it to an
		Open-Browser -Groups list. This is the swagger-tab logic that used to live inline inside
		Open-Workspace, extracted so it can be reused anywhere a project's Swagger UI tab needs
		to be opened.

		By default it also performs an idempotency check (via Test-BrowserGroupAlreadyOpen) and
		returns $null when the project's Swagger tab is already open, so the caller never opens a
		duplicate. Pass -SkipDuplicateCheck to get the pure config lookup (group name only).

		Returns $null when the project has no Swagger entry, when no project name is supplied,
		or when the tab is already open.

	.PARAMETER Project
		The project name to map. Accepts an array (the first non-empty element is used, mirroring
		how a workspace passes either an explicit -Project or the projects selected by Open-Project).

	.PARAMETER Browser
		Browser to check against. Defaults to $Configuration.Universal.DefaultBrowser.

	.PARAMETER CachedBrowserWindows
		Pre-fetched window handle list, forwarded to Test-BrowserGroupAlreadyOpen to avoid a
		second window enumeration. When omitted, the windows are enumerated as needed.

	.PARAMETER SkipDuplicateCheck
		Return the resolved group name without checking whether the tab is already open.

	.EXAMPLE
		$group = Resolve-SwaggerBrowserGroup -Project "Asseto"
		if ($group) { Open-Browser $group }

	.EXAMPLE
		$group = Resolve-SwaggerBrowserGroup -Project $selectedProjects -Browser "Firefox"
		# Returns the swagger group name to append to an existing Open-Browser -Groups list, or
		# $null if the project has no swagger entry or the tab is already open.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string[]]$Project,

		[Parameter()]
		[string]$Browser,

		[Parameter()]
		[array]$CachedBrowserWindows,

		[Parameter()]
		[switch]$SkipDuplicateCheck
	)

	try {
		# Normalize to a single project name (first non-empty wins, matching the workspace's behavior)
		$projectName = $Project | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
		if ([string]::IsNullOrWhiteSpace($projectName)) {
			return $null
		}

		# Find the BrowserGroups "Swagger" parent group, then the entry for this project
		$swaggerParentGroup = $Configuration.BrowserGroups | Where-Object { $_.Keys -contains "Swagger" } | Select-Object -First 1
		if (-not $swaggerParentGroup) {
			return $null
		}

		$swaggerItem = $swaggerParentGroup["Swagger"] | Where-Object { $_.Name -ieq $projectName } | Select-Object -First 1
		if (-not $swaggerItem) {
			Write-LogDebug " [Resolve-SwaggerBrowserGroup] No Swagger group for project [$projectName]"
			return $null
		}

		# Use the config-cased Name so downstream lookups (Open-Browser, layout) stay consistent
		$swaggerGroup = $swaggerItem.Name
		$swaggerUrls = @($swaggerItem.Url | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

		if ($SkipDuplicateCheck) {
			return $swaggerGroup
		}

		# Resolve the browser (explicit wins, else configured default)
		if ([string]::IsNullOrWhiteSpace($Browser)) {
			$Browser = $Configuration.Universal.DefaultBrowser
		}

		# Skip if the project's Swagger tab is already open (avoid duplicates on re-run)
		if ($swaggerUrls.Count -gt 0) {
			if (-not $CachedBrowserWindows) {
				$swaggerProcessName = switch ($Browser) {
					"Chrome" { "chrome" }
					"Firefox" { "firefox" }
					"Edge" { "msedge" }
					"Tor" { "firefox" }
					default { $Browser.ToLower() }
				}
				$CachedBrowserWindows = @(Get-WindowHandle -ProcessName $swaggerProcessName -ErrorAction SilentlyContinue)

				Write-LogDebug " [Resolve-SwaggerBrowserGroup] Duplicate check => cached $($CachedBrowserWindows.Count) [$swaggerProcessName] window(s) for [$swaggerGroup]"
			}

			$testParams = @{
				Urls             = $swaggerUrls
				Browser          = $Browser
				GroupDisplayName = $swaggerGroup
			}
			if ($CachedBrowserWindows) { $testParams['CachedBrowserWindows'] = $CachedBrowserWindows }

			if (Test-BrowserGroupAlreadyOpen @testParams) {
				Write-LogDebug " [Resolve-SwaggerBrowserGroup] Swagger [$swaggerGroup] already open => skipping" -Style Warning
				return $null
			}
		}

		Write-LogDebug " [Resolve-SwaggerBrowserGroup] Swagger [$swaggerGroup] resolved for project [$projectName]"
		return $swaggerGroup
	}
	catch {
		# Swagger is non-critical: surface the failure (visibly, unlike verbose-only debug) but
		# don't abort the workspace - just skip the tab.
		Write-LogWarning " [Resolve-SwaggerBrowserGroup] Error => $_"
		Write-LogDebug $_.ScriptStackTrace -Style Error
		return $null
	}
}
