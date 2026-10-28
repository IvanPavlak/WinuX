function Resolve-UpstreamRemote {
	<#
	.SYNOPSIS
		Finds the git remote of an upstream by its manifest URL, or says which command adds it.

	.DESCRIPTION
		A clone may know an upstream under any remote name (an older clone calls WinuX "upstream"),
		so the remote is found by URL first: the remote whose URL matches the manifest's wins,
		whatever it is called. Only then is a remote named after the upstream used, and only when
		its URL matches too. URLs are compared normalized: case, a user name in an https URL
		(https://you@github.com/...), a trailing / or .git, and the scp form git@host:owner/repo
		make no difference.

		Nothing is written: when no remote fits, the result carries the one command that fixes it
		(git remote add NAME URL, or git remote set-url NAME URL when a remote of that name points
		elsewhere), for the owner to run.

	.PARAMETER Name
		The upstream's name (the manifest's name line).

	.PARAMETER Url
		The upstream's URL (the manifest's url line). Without one, only a remote named Name is used.

	.PARAMETER Remotes
		The clone's remotes: a hashtable of remote name to fetch URL.

	.OUTPUTS
		[pscustomobject] with Remote (the remote name, or $null) and Fix (the command to run, or $null).

	.EXAMPLE
		Resolve-UpstreamRemote -Name 'winux' -Url 'https://github.com/IvanPavlak/WinuX.git' -Remotes @{ upstream = 'https://github.com/IvanPavlak/WinuX.git' }
		Returns Remote upstream: the URL matches, so the old name keeps working.

	.EXAMPLE
		Resolve-UpstreamRemote -Name 'foundation' -Url 'https://github.com/IvanPavlak/Foundation.git' -Remotes @{ origin = 'https://github.com/You/MyRepo.git' }
		Returns Fix "git remote add foundation https://github.com/IvanPavlak/Foundation.git".
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[AllowNull()]
		[AllowEmptyString()]
		[string]$Url,

		[AllowNull()]
		[hashtable]$Remotes = @{}
	)

	$normalize = {
		param([string]$Value)
		if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
		$v = $Value.Trim().ToLowerInvariant()
		if ($v -match '^[^/@:]+@([^:/]+):(.+)$') { $v = "https://$($Matches[1])/$($Matches[2])" }
		$v = $v -replace '^(ssh|git)://([^@/]+@)?', 'https://'
		$v = $v -replace '^(https?://)[^@/]+@', '$1'
		$v = $v.TrimEnd('/')
		if ($v.EndsWith('.git')) { $v = $v.Substring(0, $v.Length - 4) }
		return $v.TrimEnd('/')
	}

	if (-not $Remotes) { $Remotes = @{} }
	$wanted = & $normalize $Url

	if ($wanted) {
		$byUrl = @($Remotes.Keys | Sort-Object | Where-Object { (& $normalize $Remotes[$_]) -eq $wanted })
		if ($byUrl.Count -gt 0) {
			$preferred = if ($byUrl -contains $Name) { $Name } else { $byUrl[0] }
			return [pscustomobject]@{ Remote = $preferred; Fix = $null }
		}
	}

	if ($Remotes.ContainsKey($Name)) {
		if (-not $wanted) { return [pscustomobject]@{ Remote = $Name; Fix = $null } }
		return [pscustomobject]@{ Remote = $null; Fix = "git remote set-url $Name $Url" }
	}

	$fix = if ($Url) { "git remote add $Name $Url" } else { $null }
	return [pscustomobject]@{ Remote = $null; Fix = $fix }
}
