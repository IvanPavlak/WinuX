function Test-GitRepository {
	<#
	.SYNOPSIS
		Tells whether a path is inside a git repository, by walking up to the root looking for
		a .git entry.

	.DESCRIPTION
		Returns $true when the given directory - or any of its ancestors - contains a `.git`
		entry, which is what "this shell is inside a repository" means. Both shapes count: the
		ordinary `.git` DIRECTORY of a normal clone, and the `.git` FILE a worktree or a
		submodule carries (a one-line `gitdir: ...` pointer). Neither is opened; the test is
		`Test-Path` and nothing else.

		No process is spawned. `git rev-parse --is-inside-work-tree` answers the same question
		more thoroughly - it knows about `GIT_DIR`, `.git` files pointing nowhere, and the
		ceiling directories - but it costs a process launch, and this runs on every
		Show-TerminalGreeting call and therefore on every `c` and every shell start. The walk is
		a handful of stat calls and is not measurable.

		A path that does not exist is not an error: the walk simply finds no `.git` above it and
		returns $false, so a caller can pass a stale $PWD without guarding it.

	.PARAMETER Path
		The directory to start the walk at. Defaults to the current location. A file path works
		as long as its directory exists - the walk starts there once the leaf turns out not to
		be a directory.

	.OUTPUTS
		[bool] - $true when a .git entry was found at or above Path.

	.EXAMPLE
		Test-GitRepository
		Tells whether the current directory is inside a repository.

	.EXAMPLE
		Test-GitRepository -Path "C:\Users\Ivan\Development\GitHub\Dotfiles\Windows"
		$true - the .git directory one level up is found by the walk.

	.EXAMPLE
		if (Test-GitRepository) { onefetch }
		The guard Invoke-Onefetch is built on.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Path = $PWD.Path
	)

	if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

	# Resolve to a directory to start from. A file path starts at its parent; a path that does
	# not exist is walked as written, which simply finds nothing.
	try {
		$current = if (Test-Path -LiteralPath $Path -PathType Leaf) {
			Split-Path -Parent $Path
		}
		else {
			$Path
		}
	}
	catch {
		$current = $Path
	}

	while (-not [string]::IsNullOrWhiteSpace($current)) {
		if (Test-Path -LiteralPath (Join-Path $current ".git")) { return $true }

		# Split-Path returns "" at a drive root ("C:\"), which ends the walk - but it THROWS on a
		# bare qualifier ("C:", no separator), which is what Split-Path -Qualifier hands back and
		# therefore something a caller can pass. A path with nothing above it is the end of the
		# walk either way, so the throw is treated as one rather than escaping to the prompt.
		$parent = try { Split-Path -Parent $current } catch { "" }
		if ($parent -eq $current) { break }
		$current = $parent
	}

	return $false
}
