function Get-ChangedPaths {
	<#
	.SYNOPSIS
		The repository paths that changed since a base: committed, staged, unstaged and untracked.

	.DESCRIPTION
		The input to Run-Tests -Changed. The base is the merge base of HEAD with -Since (default:
		master, then origin/master, main, origin/main - the first that exists). Against it, every
		path that differs in the working tree counts - which covers the branch's commits and any
		staged or unstaged edit in one diff - plus every untracked file that is not ignored.
		Renames count as both the old and the new path, so a moved function still selects the tests
		of whatever called it by its old name.

		Read-only git: rev-parse, merge-base, diff and ls-files. Never throws; when git cannot answer
		(not a repository, unknown ref), Error says why and the caller runs everything.

	.PARAMETER RepositoryRoot
		Any directory inside the repository.

	.PARAMETER Since
		The ref to compare against. Defaults to the main branch.

	.OUTPUTS
		[pscustomobject] Root (the repository's top level), Base (the commit compared against),
		BaseRef (the ref it came from), Paths (every changed path, repository-relative, forward
		slashes), Added and Deleted (the subsets that are new or gone), Error.

	.EXAMPLE
		Get-ChangedPaths -RepositoryRoot $PSScriptRoot
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$RepositoryRoot,

		[Parameter()]
		[string]$Since
	)

	$fail = { param([string]$Message) [pscustomobject]@{ Root = $null; Base = $null; BaseRef = $Since; Paths = @(); Added = @(); Deleted = @(); Error = $Message } }

	try {
		$root = @(git -C $RepositoryRoot rev-parse --show-toplevel 2>$null)[0]
		if ($LASTEXITCODE -ne 0 -or -not $root) { return & $fail "not a git repository: $RepositoryRoot" }
		$root = $root.Trim() -replace '/', [System.IO.Path]::DirectorySeparatorChar

		$candidates = if ($Since) { @($Since) } else { @('master', 'origin/master', 'main', 'origin/main') }
		$baseRef = $null
		foreach ($candidate in $candidates) {
			git -C $root rev-parse --verify --quiet "$candidate^{commit}" 2>$null | Out-Null
			if ($LASTEXITCODE -eq 0) { $baseRef = $candidate; break }
		}
		if (-not $baseRef) { return & $fail "no such ref: $($candidates -join ', ')" }

		$base = @(git -C $root merge-base HEAD $baseRef 2>$null)[0]
		if ($LASTEXITCODE -ne 0 -or -not $base) {
			$base = @(git -C $root rev-parse --verify --quiet "$baseRef^{commit}" 2>$null)[0]
		}
		$base = "$base".Trim()

		$statusLines = @(git -C $root -c core.quotepath=off diff --name-status --no-renames $base -- 2>$null)
		if ($LASTEXITCODE -ne 0) { return & $fail "git diff against $baseRef failed" }
		$untracked = @(git -C $root -c core.quotepath=off ls-files --others --exclude-standard 2>$null)

		$paths = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		$added = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		$deleted = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		foreach ($line in $statusLines) {
			if (-not $line) { continue }
			$parts = $line -split "`t", 2
			if ($parts.Count -lt 2) { continue }
			$path = $parts[1].Trim() -replace '\\', '/'
			[void]$paths.Add($path)
			if ($parts[0] -like 'A*') { [void]$added.Add($path) }
			if ($parts[0] -like 'D*') { [void]$deleted.Add($path) }
		}
		foreach ($line in $untracked) {
			if (-not $line) { continue }
			$path = $line.Trim() -replace '\\', '/'
			[void]$paths.Add($path)
			[void]$added.Add($path)
		}

		return [pscustomobject]@{ Root = $root; Base = $base; BaseRef = $baseRef; Paths = [string[]]@($paths); Added = [string[]]@($added); Deleted = [string[]]@($deleted); Error = $null }
	}
	catch {
		return & $fail $_.Exception.Message
	}
}
