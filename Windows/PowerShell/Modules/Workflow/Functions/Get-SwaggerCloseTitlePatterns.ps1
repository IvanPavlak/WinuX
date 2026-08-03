function Get-SwaggerCloseTitlePatterns {
	<#
	.SYNOPSIS
		Returns the swagger-specific browser tab title patterns to close for a project.

	.DESCRIPTION
		Maps a project name to its entry in the BrowserGroups "Swagger" group (case-insensitive
		match on the entry's Name) and returns the regex patterns Close-Project should hand to
		Close-BrowserTabsByPattern for that project's Swagger tab:

		- no Swagger entry (or no Swagger group at all) => empty (a setup without swagger
		  configuration gets zero swagger behavior)
		- a Swagger entry exists => "(?i)swagger ui" (backend running renders that title)
		- any of its URLs is localhost => additionally "(?i)problem loading page" (backend
		  not running renders a failed-load tab)

		This is the swagger-closing logic that used to live inline inside Close-Project,
		extracted so Close-Project stays thin and the logic can be reused.

	.PARAMETER Project
		The project name to map.

	.EXAMPLE
		$patterns += @(Get-SwaggerCloseTitlePatterns -Project "MyProject")
		# Appends the swagger patterns (if any) to an existing pattern list

	.OUTPUTS
		String[]. The title regex patterns; empty when the project has no Swagger entry.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Project
	)

	$patterns = @()

	# Check if there's a swagger group matching this project (case-insensitive)
	$urlGroups = $Configuration.BrowserGroups
	$swaggerParentGroup = $urlGroups | Where-Object { $_.Keys -contains "Swagger" }
	$swaggerGroup = if ($swaggerParentGroup) {
		($swaggerParentGroup["Swagger"] | Where-Object { $_.Name -ieq $Project }).Name
	}
	if ($swaggerGroup) {
		Write-LogDebug " [Get-SwaggerCloseTitlePatterns] Found swagger group => [$swaggerGroup]"

		# Get the swagger URLs
		$swaggerUrls = $null
		if ($swaggerParentGroup) {
			$swaggerItems = $swaggerParentGroup["Swagger"]
			$swaggerItem = $swaggerItems | Where-Object { $_.Name -eq $swaggerGroup }

			if ($swaggerItem) {
				$swaggerUrls = @($swaggerItem.Url)
			}
		}

		if ($swaggerUrls) {
			Write-LogDebug " [Get-SwaggerCloseTitlePatterns] Swagger URLs => $($swaggerUrls -join ', ')" -Style Step

			# Check if any URLs are localhost (for swagger detection)
			$hasLocalhostUrls = $swaggerUrls | Where-Object {
				try {
					$uri = [System.Uri]$_
					$uri.Host -eq "localhost" -or $uri.Host -eq "127.0.0.1"
				}
				catch {
					$false
				}
			}

			if (Test-LogVerbose) {
				$localhostStatus = if ($hasLocalhostUrls) { "YES" } else { "NO" }
				Write-LogDebug " [Get-SwaggerCloseTitlePatterns] Has localhost URLs => [$localhostStatus]" -Style Step
			}

			# Add swagger-specific patterns
			$patterns += "(?i)swagger ui"
			if ($hasLocalhostUrls) {
				$patterns += "(?i)problem loading page"
			}
		}
	}

	return $patterns
}
