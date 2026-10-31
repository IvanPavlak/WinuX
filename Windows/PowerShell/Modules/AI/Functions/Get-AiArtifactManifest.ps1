function Get-AiArtifactManifest {
	<#
	.SYNOPSIS
		Reads an AI artifact manifest: the tab-separated list of pinned third-party items a manifest source names.

	.DESCRIPTION
		The format, shared with Foundation and with the repositories that publish a manifest:

		  - UTF-8, tab-separated, one header row, `#` starts a comment line, blank lines are
		    ignored.
		  - Columns, in order: name, kind, scope, source, ref, path, install.
		      name     the item's folder name in its source; also its installed name unless
		               install gives rename=<new-name>
		      kind     skills, mods, rules, prompts or agents
		      scope    * (every profile), profile names separated by commas, or repo:<name>
		               for an item linked into one repository only
		      source   https://github.com/<owner>/<repo>
		      ref      a full 40-character commit SHA, never a branch
		      path     the item's folder inside the source
		      install  clone, optionally followed by rename=<new-name> and/or
		               strip-invocation-guard (separated by spaces or commas)

		A row that breaks the format is left out with a problem naming its line, so one bad row
		never hides the rest. Nothing is fetched or written.

		Returns @{ Path; Rows; Problems }. Each row is @{ Line; Name; LinkName; Kind; Scope;
		Repository; Source; Owner; Repo; Ref; Path; Rename; StripInvocationGuard }: Scope the
		list of scope tokens (profile names, *, or one repo:<name>), Repository the repository
		name of a repo: row (empty otherwise), LinkName the installed name (Rename, else Name).
		A missing file yields no rows and one problem.

	.PARAMETER Path
		The manifest file to read.

	.EXAMPLE
		(Get-AiArtifactManifest -Path "C:\Users\You\Development\GitHub\MySkills\third-party\manifest.tsv").Rows
		Returns every valid row of the manifest.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Path
	)

	$result = @{
		Path     = $Path
		Rows     = @()
		Problems = @()
	}

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		$result.Problems += "Manifest not found => [$Path]"
		return $result
	}

	$kinds = @('skills', 'mods', 'rules', 'prompts', 'agents')
	$lines = [IO.File]::ReadAllLines($Path, [Text.UTF8Encoding]::new($false))
	$headerSeen = $false
	$names = @{}

	for ($index = 0; $index -lt $lines.Count; $index++) {
		$lineNumber = $index + 1
		$line = $lines[$index].TrimEnd("`r")
		if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }

		$cells = @($line.Split("`t") | ForEach-Object { $_.Trim() })
		if (-not $headerSeen) {
			$headerSeen = $true
			if ($cells[0] -eq 'name') { continue }
			$result.Problems += "Line ${lineNumber}: the first row is not the header (name, kind, scope, source, ref, path, install) - read as a row"
		}

		$problems = @()
		if ($cells.Count -ne 7) {
			$result.Problems += "Line ${lineNumber}: $($cells.Count) column(s), 7 expected - skipped"
			continue
		}
		$name, $kind, $scopeText, $source, $ref, $itemPath, $install = $cells
		$kind = $kind.ToLowerInvariant()

		if ($name -notmatch '^[A-Za-z0-9._-]+$') { $problems += "name [$name] is not a folder name" }
		if ($kinds -notcontains $kind) { $problems += "kind [$kind] is not one of $($kinds -join ', ')" }
		$owner = ''
		$repo = ''
		if ($source -match '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?/?$') {
			$owner = $Matches[1]
			$repo = $Matches[2]
		}
		else {
			$problems += "source [$source] is not https://github.com/<owner>/<repo>"
		}
		if ($ref -notmatch '^[0-9a-f]{40}$') { $problems += "ref [$ref] is not a full commit SHA" }
		$normalisedPath = $itemPath.Replace('\', '/').Trim('/')
		if (-not $normalisedPath -or @($normalisedPath.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
			$problems += "path [$itemPath] is empty or leaves the source"
		}

		$scope = @($scopeText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
		$repository = ''
		$repoTokens = @($scope | Where-Object { $_ -like 'repo:*' })
		if ($scope.Count -eq 0) {
			$problems += "scope is empty"
		}
		elseif ($repoTokens.Count -gt 0) {
			if ($scope.Count -gt 1) { $problems += "scope [$scopeText] mixes repo:<name> with other entries" }
			$repository = $repoTokens[0].Substring(5).Trim()
			if (-not $repository) { $problems += "scope [$scopeText] names no repository" }
		}

		$rename = ''
		$strip = $false
		$tokens = @($install -split '[\s,]+' | Where-Object { $_ })
		if ($tokens.Count -eq 0 -or $tokens[0] -ne 'clone') {
			$problems += "install [$install] does not start with clone"
		}
		foreach ($token in @($tokens | Select-Object -Skip 1)) {
			if ($token -eq 'strip-invocation-guard') { $strip = $true }
			elseif ($token -like 'rename=*') {
				$rename = $token.Substring(7)
				if ($rename -notmatch '^[A-Za-z0-9._-]+$') { $problems += "rename [$rename] is not a folder name" }
			}
			else { $problems += "install option [$token] is unknown" }
		}

		if ($problems.Count -gt 0) {
			$result.Problems += "Line ${lineNumber}: $($problems -join '; ') - skipped"
			continue
		}

		$linkName = if ($rename) { $rename } else { $name }
		$nameKey = "$kind|$($scope -join ',')|$($linkName.ToLowerInvariant())"
		if ($names.ContainsKey($nameKey)) {
			$result.Problems += "Line ${lineNumber}: $kind [$linkName] is already installed by line $($names[$nameKey]) for the same scope - skipped"
			continue
		}
		$names[$nameKey] = $lineNumber

		$result.Rows += @{
			Line                 = $lineNumber
			Name                 = $name
			LinkName             = $linkName
			Kind                 = $kind
			Scope                = $scope
			Repository           = $repository
			Source               = "https://github.com/$owner/$repo"
			Owner                = $owner
			Repo                 = $repo
			Ref                  = $ref
			Path                 = $normalisedPath
			Rename               = $rename
			StripInvocationGuard = $strip
		}
	}

	return $result
}
