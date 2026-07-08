function Get-DbContextsFromProject {
	<#
	.SYNOPSIS
		Finds DbContext class names in a C# project directory.

	.DESCRIPTION
		Scans .cs files (excluding bin/obj) and returns unique class names that inherit
		from DbContext, including fully-qualified variants when namespace is available.

	.PARAMETER ProjectPath
		Path to the project directory to scan.

	.EXAMPLE
		Get-DbContextsFromProject -ProjectPath "C:\src\Api"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$ProjectPath
	)

	if (-not (Test-Path -Path $ProjectPath -PathType Container)) {
		return @()
	}

	$contextResults = @()
	$csFiles = Get-ChildItem -Path $ProjectPath -Recurse -Filter "*.cs" -File -ErrorAction SilentlyContinue |
		Where-Object {
			$fullName = $_.FullName
			$fullName -notmatch "[\\/]bin[\\/]" -and $fullName -notmatch "[\\/]obj[\\/]"
		}

	foreach ($file in $csFiles) {
		$content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
		if (-not $content) { continue }

		$namespaceMatch = [regex]::Match($content, '(?m)^\s*namespace\s+([\w\.]+)\s*[;\{]')
		$namespaceName = if ($namespaceMatch.Success) { $namespaceMatch.Groups[1].Value } else { $null }

		$classMatches = [regex]::Matches($content, '(?m)^\s*(?:public|internal|protected|private)?\s*(?:abstract\s+|sealed\s+|partial\s+)*class\s+([A-Za-z_]\w*)\s*:\s*(?:[A-Za-z_]\w*\.)*DbContext\b')
		foreach ($match in $classMatches) {
			$className = $match.Groups[1].Value
			$contextResults += $className

			if ($namespaceName) {
				$contextResults += "$namespaceName.$className"
			}
		}
	}

	return @($contextResults | Sort-Object -Unique)
}
