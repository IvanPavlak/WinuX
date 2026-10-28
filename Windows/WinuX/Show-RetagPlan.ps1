<#
.SYNOPSIS
	Prints the one-time plan that moves WinuX's bare release tags (v1.9.0) under its prefix
	(winux/v1.9.0), and the commands that carry it out. Runs nothing that changes a tag or a release.

.DESCRIPTION
	Since 2.0.0 every upstream tags its releases with its own prefix, so a fork of several upstreams
	fetches all of them with a plain git fetch and no tag clashes (Windows/VERSIONING.md, "Tag names").
	The tags published before that are bare. This script lists them in release order - every
	vX.Y.Z (and vX.Y.Z-pre) tag of the repository, oldest first - with the commit each points at,
	the prefixed name it becomes, and then prints, for the owner to run by hand:

	1. git tag -a <prefix>/vX.Y.Z -m <prefix>/vX.Y.Z <commit> for every tag (same commits)
	2. git push origin <every new tag>
	3. gh release edit vX.Y.Z --tag <prefix>/vX.Y.Z for every release (re-points the release)
	4. git push origin --delete <every bare tag>, then git tag -d for each

	Run it with no arguments first (the dry run is all it ever does), read the pairs, then run the
	printed commands in order. A tag already prefixed is skipped, so running it again after a partial
	retag prints only what is left.

.PARAMETER RepositoryRoot
	The repository whose tags to move. Defaults to the repository this script lives in.

.PARAMETER Prefix
	The tag prefix. Defaults to the tag-prefix of Windows/PowerShell/Upstream.conf (winux).

.EXAMPLE
	.\Windows\WinuX\Show-RetagPlan.ps1
	Prints v0.1.0 -> winux/v0.1.0 ... v1.9.0 -> winux/v1.9.0 and the commands that do it.
#>
[CmdletBinding()]
param(
	[string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
	[string]$Prefix
)

if (-not $Prefix) {
	$manifest = Join-Path $RepositoryRoot 'Windows\PowerShell\Upstream.conf'
	$line = Get-Content -LiteralPath $manifest | Where-Object { $_ -match '^\s*tag-prefix\s+(\S+)' } | Select-Object -First 1
	if ($line -match '^\s*tag-prefix\s+(\S+)') { $Prefix = $Matches[1] }
}
if (-not $Prefix) { throw "No tag prefix - pass -Prefix or set tag-prefix in Windows/PowerShell/Upstream.conf" }

& git -C $RepositoryRoot fetch --tags -q origin 2>$null
$bare = @(& git -C $RepositoryRoot tag -l 'v*' | Where-Object { $_ -match '^v(\d+)\.(\d+)\.(\d+)(-.+)?$' })
if ($bare.Count -eq 0) {
	Write-Output "No bare v* tags left - nothing to move."
	return
}

# SemVer order: release versions by number, a pre-release before its release.
$ordered = $bare | Sort-Object -Property @(
	@{ Expression = { $null = $_ -match '^v(\d+)\.(\d+)\.(\d+)(-.+)?$'; [int]$Matches[1] } },
	@{ Expression = { $null = $_ -match '^v(\d+)\.(\d+)\.(\d+)(-.+)?$'; [int]$Matches[2] } },
	@{ Expression = { $null = $_ -match '^v(\d+)\.(\d+)\.(\d+)(-.+)?$'; [int]$Matches[3] } },
	@{ Expression = { $null = $_ -match '^v(\d+)\.(\d+)\.(\d+)(-.+)?$'; if ($Matches[4]) { 0 } else { 1 } } },
	@{ Expression = { $_ } }
)

$plan = foreach ($tag in $ordered) {
	[pscustomobject]@{
		Old    = $tag
		New    = "$Prefix/$tag"
		Commit = (& git -C $RepositoryRoot rev-list -n 1 $tag)
	}
}

Write-Output "Tags to move under '$Prefix/' (release order, same commits):"
foreach ($step in $plan) { Write-Output ("  {0,-14} -> {1,-22} {2}" -f $step.Old, $step.New, $step.Commit.Substring(0, 12)) }

Write-Output ""
Write-Output "Commands (run them yourself, in order; this script ran none of them):"
Write-Output ""
foreach ($step in $plan) { Write-Output "git tag -a $($step.New) -m `"$($step.New)`" $($step.Commit)" }
Write-Output "git push origin $(@($plan.New) -join ' ')"
foreach ($step in $plan) { Write-Output "gh release edit $($step.Old) --tag $($step.New)" }
Write-Output "git push origin --delete $(@($plan.Old) -join ' ')"
foreach ($step in $plan) { Write-Output "git tag -d $($step.Old)" }
