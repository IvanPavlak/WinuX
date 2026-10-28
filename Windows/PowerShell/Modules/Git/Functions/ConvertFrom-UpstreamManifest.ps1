function ConvertFrom-UpstreamManifest {
	<#
	.SYNOPSIS
		Parses an upstream manifest (upstream.conf) or a fork's upstreams.local.conf into an object.

	.DESCRIPTION
		Both files are plain "KEY VALUE" lines: blank lines and lines starting with # are skipped,
		and the first run of whitespace separates the key from its value. A manifest names one
		upstream and its paths:

		- name, url, tag-prefix, changelog - one value each (the last one wins)
		- own PATH, mirror PATH - repeatable; a PATH ending in / is a folder prefix, any other one file

		A fork's Git/upstreams.local.conf holds the fork's own choices, parsed by the same function:

		- root-owner NAME | fork - who owns the hallway (every path no manifest owns or mirrors)
		- take UPSTREAM PATH - repeatable; adopts a hallway path from that upstream as if it were
		  that upstream's own

		Unknown keys are ignored, so an older reader does not fail on a newer file. The function
		reads only text, never git or the disk; Merge-Upstreams hands it what git show returned.

	.PARAMETER Text
		The file's text. Null or empty returns an object with no values.

	.OUTPUTS
		[pscustomobject] with Name, Url, TagPrefix, Changelog, Own, Mirror, RootOwner and Take (an
		array of objects with Upstream and Path).

	.EXAMPLE
		ConvertFrom-UpstreamManifest -Text (Get-Content -Raw Windows\PowerShell\Upstream.conf)
		Returns WinuX's manifest: Name winux, its own folders and the mirror list.

	.EXAMPLE
		(ConvertFrom-UpstreamManifest -Text "root-owner fork`ntake winux .github/ISSUE_TEMPLATE/").Take
		Returns one take entry: Upstream winux, Path .github/ISSUE_TEMPLATE/.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Text
	)

	$manifest = [pscustomobject]@{
		Name      = $null
		Url       = $null
		TagPrefix = $null
		Changelog = $null
		Own       = @()
		Mirror    = @()
		RootOwner = $null
		Take      = @()
	}
	if ([string]::IsNullOrEmpty($Text)) { return $manifest }

	foreach ($rawLine in ($Text -split "`r?`n")) {
		$line = $rawLine.Trim()
		if ($line -eq '' -or $line.StartsWith('#')) { continue }
		$parts = $line -split '\s+', 2
		$key = $parts[0].ToLowerInvariant()
		$value = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
		if ($value -eq '') { continue }

		switch ($key) {
			'name' { $manifest.Name = $value }
			'url' { $manifest.Url = $value }
			'tag-prefix' { $manifest.TagPrefix = $value }
			'changelog' { $manifest.Changelog = $value }
			'own' { $manifest.Own += $value }
			'mirror' { $manifest.Mirror += $value }
			'root-owner' { $manifest.RootOwner = $value }
			'take' {
				$takeParts = $value -split '\s+', 2
				if ($takeParts.Count -eq 2 -and $takeParts[1].Trim() -ne '') {
					$manifest.Take += [pscustomobject]@{ Upstream = $takeParts[0]; Path = $takeParts[1].Trim() }
				}
			}
		}
	}

	return $manifest
}
