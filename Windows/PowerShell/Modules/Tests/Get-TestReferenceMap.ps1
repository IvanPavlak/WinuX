function Get-TestReferenceMap {
	<#
	.SYNOPSIS
		Which of a set of names each PowerShell file references, read off its tokens and cached.

	.DESCRIPTION
		The static half of Run-Tests -Changed. Every file is tokenized with the PowerShell parser
		and every token except comments is split into name-shaped pieces: command names, bare
		words, and the contents of strings - so `& 'Open-Workspace'`, a workspace action written
		as a string, and `. "$FunctionsPath\Add-PositionedWindow.ps1"` all count as references,
		exactly as a call does. A piece that equals one of -Names is a reference.

		This deliberately over-approximates: a name that is merely mentioned in a string counts.
		Selecting a test too many costs seconds; missing one costs a regression.

		The result is cached in -CachePath, keyed by each file's SHA-256 and by a hash of the name
		set, so only changed files are re-parsed and adding or removing a function re-parses
		everything once. A missing or corrupt cache is rebuilt; failing to write it is ignored.

		Get-PowerShellFunctionDependencies is not reusable here: it works on loaded commands and
		keeps script state, and this runs with no WinuX module loaded.

	.PARAMETER Path
		Full paths of the files to read.

	.PARAMETER Names
		The names to look for (function names and fixture base names). Case-insensitive.

	.PARAMETER RootPath
		Paths are cached relative to this root.

	.PARAMETER CachePath
		The cache file (Results\dependency-map.json); omit to parse without caching.

	.OUTPUTS
		[hashtable] full path -> string[] of the names that file references.

	.EXAMPLE
		Get-TestReferenceMap -Path $files -Names $functionNames -RootPath $powerShellRoot -CachePath $cache
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[string[]]$Path,

		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[string[]]$Names,

		[Parameter(Mandatory = $true)]
		[string]$RootPath,

		[Parameter()]
		[string]$CachePath
	)

	$nameSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	foreach ($name in $Names) { if ($name) { [void]$nameSet.Add($name) } }
	$sortedNames = @($nameSet | Sort-Object)
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		# The extraction rules are part of the key: changing them must invalidate every cached entry.
		$namesHash = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(("rules-v2`n" + ($sortedNames -join "`n")))))
	}
	finally { $sha.Dispose() }

	$cached = @{}
	if ($CachePath -and (Test-Path -LiteralPath $CachePath)) {
		try {
			$document = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
			if ($document.namesHash -eq $namesHash -and $document.files) {
				foreach ($property in $document.files.PSObject.Properties) { $cached[$property.Name] = $property.Value }
			}
		}
		catch { $cached = @{} }
	}

	# Name-shaped runs of characters. A run directly followed by a path separator is a folder in a
	# path ("$ModuleRoot\Bootstrap\Functions\X.ps1"), never a reference to a function of the same
	# name, so it is skipped; the file name at the end of the path still counts.
	$namePattern = [regex]::new('[A-Za-z0-9_\-]+(?![A-Za-z0-9_\-]|[\\/])')
	$result = @{}
	$fresh = [ordered]@{}
	$changed = $false

	foreach ($file in $Path) {
		if (-not (Test-Path -LiteralPath $file)) { continue }
		$relative = $file
		if ($relative.StartsWith($RootPath, [StringComparison]::OrdinalIgnoreCase)) { $relative = $relative.Substring($RootPath.Length).TrimStart('\', '/') }
		$relative = $relative -replace '\\', '/'

		$hash = $null
		try { $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash } catch { }

		$entry = $cached[$relative]
		if ($entry -and $hash -and $entry.hash -eq $hash) {
			$references = @($entry.refs)
		}
		else {
			$changed = $true
			$found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
			$tokens = $null
			$errors = $null
			[void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
			foreach ($token in $tokens) {
				if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }
				$text = if ($token -is [System.Management.Automation.Language.StringToken]) { $token.Value } else { $token.Text }
				if (-not $text) { continue }
				foreach ($match in $namePattern.Matches($text)) {
					$piece = $match.Value
					if ($piece.Length -gt 1 -and $nameSet.Contains($piece)) { [void]$found.Add($piece) }
				}
			}
			$references = @($found | Sort-Object)
		}

		$result[$file] = [string[]]$references
		$fresh[$relative] = [ordered]@{ hash = $hash; refs = [string[]]$references }
	}

	if ($CachePath -and ($changed -or $fresh.Count -ne $cached.Count)) {
		try {
			$directory = Split-Path -Path $CachePath -Parent
			if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
			$temporary = "$CachePath.$PID.tmp"
			$json = [ordered]@{ namesHash = $namesHash; files = $fresh } | ConvertTo-Json -Depth 5 -Compress
			[System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
			Move-Item -LiteralPath $temporary -Destination $CachePath -Force -ErrorAction Stop
		}
		catch { }
	}

	return $result
}
