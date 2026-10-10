function Get-WorkingTreeFingerprint {
	<#
	.SYNOPSIS
		A hash that identifies exactly what is in the working tree: HEAD plus every uncommitted change.

	.DESCRIPTION
		The gate stamp (Results\last-green.json) records this for every green full run, and a
		-Changed or -Quick run compares against it to remind you when the tree you are about to
		merge has no green full run yet. Two trees get the same fingerprint only when HEAD is the
		same commit and every modified, deleted and untracked (not ignored) file has the same
		content - so it changes on any edit, and does not change when nothing did.

		Read-only git: rev-parse, status and hash-object. Never throws; returns $null when git
		cannot answer.

	.PARAMETER RepositoryRoot
		Any directory inside the repository.

	.OUTPUTS
		[pscustomobject] Head (commit id), Fingerprint (hex SHA-256), or $null.

	.EXAMPLE
		(Get-WorkingTreeFingerprint -RepositoryRoot $root).Fingerprint
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$RepositoryRoot
	)

	try {
		$root = @(git -C $RepositoryRoot rev-parse --show-toplevel 2>$null)[0]
		if ($LASTEXITCODE -ne 0 -or -not $root) { return $null }
		$head = @(git -C $root rev-parse HEAD 2>$null)[0]
		if ($LASTEXITCODE -ne 0) { $head = 'unborn' }

		# -z keeps paths verbatim; each entry is "XY path", and a rename carries its source as the
		# next entry, which is just one more path to hash.
		$raw = (git -C $root -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all 2>$null) -join "`n"
		$entries = @($raw -split "`0" | Where-Object { $_ })
		$lines = [System.Collections.Generic.List[string]]::new()
		$existing = [System.Collections.Generic.List[string]]::new()
		foreach ($entry in $entries) {
			$path = if ($entry.Length -gt 3 -and $entry[2] -eq ' ') { $entry.Substring(3) } else { $entry }
			$status = if ($entry.Length -gt 3 -and $entry[2] -eq ' ') { $entry.Substring(0, 2) } else { 'R?' }
			$lines.Add("$status $path")
			if (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf) { $existing.Add($path) }
		}

		$ids = @{}
		if ($existing.Count -gt 0) {
			$hashes = @($existing | ForEach-Object { Join-Path $root $_ } | git -C $root hash-object --stdin-paths 2>$null)
			for ($i = 0; $i -lt $existing.Count -and $i -lt $hashes.Count; $i++) { $ids[$existing[$i]] = $hashes[$i] }
		}

		$material = [System.Text.StringBuilder]::new()
		[void]$material.Append("HEAD $head`n")
		foreach ($line in ($lines | Sort-Object)) {
			$path = $line.Substring(3)
			[void]$material.Append("$line $($ids[$path])`n")
		}

		$sha = [System.Security.Cryptography.SHA256]::Create()
		try { $fingerprint = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($material.ToString()))) }
		finally { $sha.Dispose() }

		return [pscustomobject]@{ Head = "$head".Trim(); Fingerprint = $fingerprint }
	}
	catch {
		return $null
	}
}
