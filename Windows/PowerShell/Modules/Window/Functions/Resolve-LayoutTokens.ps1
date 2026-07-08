function Resolve-LayoutTokens {
	<#
	.SYNOPSIS
		Expands layout-file tokens (e.g. "Browser") to regex patterns at the matching boundary.

	.DESCRIPTION
		Layout files (under Windows/PowerShell/Modules/Window/Layouts/**) may use the literal
		token "Browser" as a value for `ProcessName` and/or `WindowTitle`. This helper expands
		those tokens to a regex covering every browser declared in `$global:Configuration.Browsers`
		(excluding Tor - see SecureBrowser workspace for the intentional opt-out).

		Other values - including literal regex patterns like `(firefox|chrome|msedge|brave)` -
		are returned unchanged. Tokens are matched case-sensitively to avoid clashing with real
		process names. The expanded patterns are cached on the module scope to keep this cheap
		when called per layout entry inside the Set-WindowLayouts / Confirm-WorkspaceWindowPositions
		loops.

		The helper accepts a single layout entry (hashtable) and returns a shallow clone with
		expanded `ProcessName` / `WindowTitle` fields. The original entry is never mutated, so
		Visualize-Layouts and any other consumer that reads the raw layout still sees "Browser".

	.PARAMETER LayoutEntry
		A single layout entry hashtable. Typical keys: ProcessName, WindowTitle, DesktopNumber,
		Zone, Monitor, Layout.

	.EXAMPLE
		$expanded = Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "Browser"; Zone = "Left" }
		# $expanded.ProcessName -> "(firefox|chrome|msedge|brave)"

	.EXAMPLE
		$expanded = Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "firefox" }
		# $expanded.ProcessName -> "firefox" (unchanged)

	.OUTPUTS
		[hashtable] - a shallow clone of the input with token fields expanded.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[hashtable]$LayoutEntry
	)

	# Lazy-build token table on first call. Cached at module scope.
	if (-not $script:LayoutTokenCache) {
		$browserProcesses = $null
		$browserTitles = $null

		# Preferred source: $global:Configuration.Browsers (keys + Exe basenames), minus Tor.
		if ($global:Configuration -and $global:Configuration.Browsers) {
			$processSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
			$titleSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

			foreach ($entry in $global:Configuration.Browsers.GetEnumerator()) {
				$name = $entry.Key
				# Intentional exclusion: SecureBrowser_*.psd1 targets tor explicitly.
				if ($name -ieq 'Tor') { continue }

				# Title side: friendly browser name (e.g. "Firefox", "Chrome").
				[void]$titleSet.Add($name)

				# Process side: exe basename without extension (e.g. "firefox", "msedge").
				$exe = $entry.Value.Exe
				if ($exe) {
					$basename = [System.IO.Path]::GetFileNameWithoutExtension($exe)
					if ($basename) { [void]$processSet.Add($basename) }
				}
			}

			if ($processSet.Count -gt 0) { $browserProcesses = @($processSet) }
			if ($titleSet.Count -gt 0) { $browserTitles = @($titleSet) }
		}

		# Fallback when Configuration is not loaded (e.g. isolated Pester tests).
		if (-not $browserProcesses) {
			$browserProcesses = @('firefox', 'chrome', 'msedge', 'brave')
		}
		if (-not $browserTitles) {
			$browserTitles = @('Firefox', 'Chrome', 'Edge', 'Brave')
		}

		$script:LayoutTokenCache = @{
			Browser = @{
				ProcessPattern = "($($browserProcesses -join '|'))"
				TitlePattern   = "(?i)($(($browserTitles | ForEach-Object { [regex]::Escape($_) }) -join '|'))"
			}
		}
	}

	# Clone so we never mutate the caller's hashtable (layout files are loaded once and reused).
	$resolved = @{}
	foreach ($key in $LayoutEntry.Keys) {
		$resolved[$key] = $LayoutEntry[$key]
	}

	$token = $script:LayoutTokenCache['Browser']

	# Case-sensitive token match. Real process names are lowercase ("firefox"), so the
	# PascalCase token "Browser" is unambiguous.
	if ($resolved.ProcessName -ceq 'Browser') {
		$resolved.ProcessName = $token.ProcessPattern
	}
	if ($resolved.WindowTitle -ceq 'Browser') {
		$resolved.WindowTitle = $token.TitlePattern
	}

	return $resolved
}
