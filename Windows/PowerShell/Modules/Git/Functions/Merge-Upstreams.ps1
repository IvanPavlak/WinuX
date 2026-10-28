function Merge-Upstreams {
	<#
	.SYNOPSIS
		Merges one upstream into the current branch, taking only what that upstream owns, and stops
		before the commit.

	.DESCRIPTION
		A fork may merge several upstreams (WinuX for Windows, Foundation for the Mac). Each ships a
		manifest (Windows/PowerShell/Upstream.conf, Unix/config/upstream.conf) naming its rooms (own),
		the files every upstream ships identically (mirror), its URL, tag prefix and changelog. Every
		other path is the hallway, which belongs to the root owner: the fork's root-owner line in
		Git/upstreams.local.conf, else the only upstream when there is one, else the fork itself.

		Merge-Upstreams NAME resolves NAME's remote by the manifest URL first (any remote name), then
		by name; when none fits it prints the git remote add (or set-url) command and stops - it
		never writes git configuration. It refuses to start with modified tracked files or a merge
		in progress, fetches the remote's branches and the tags under its prefix only (so two
		upstreams' tags never clash), and merges REMOTE/BRANCH with --no-commit --no-ff. Every path
		the merge changed is then classified by Resolve-UpstreamPathClass, reading NAME's manifest as
		the upstream has it: own, take, mirror and hallway paths stay as merged; a declined path is
		put back as HEAD has it, or unstaged and removed when HEAD has none (empty folders pruned).
		Declined paths are listed, never silently dropped; git show REMOTE/BRANCH:PATH reads any.

		Conflicts left in taken paths are listed and the merge stays in progress (resolve, git add,
		commit - or git merge --abort). Otherwise it prints the staged summary, the suggested commit
		message (the newest released version of the upstream's changelog) and the push command,
		with a branch of its own first when on master or main. It never commits, pushes or rebases.

		A branch already contained in HEAD is up to date. A branch with no common history prints the
		one-time bridge merge for the owner to run. -DryRun merges nothing: git merge-tree computes
		the same merge into a tree of its own, so it lists exactly what the real run would take, put
		back and stop on as a conflict, and warns of every mirror file whose merged copy would differ
		from the upstream's (the mirror contract is broken; take it from the upstream that is right).
		It needs git 2.38 or newer.

		The Mac twin, Unix/modules/Git/bin/Merge-Upstreams, stages the same result.

	.PARAMETER Name
		The upstream to merge: a manifest's name (winux, foundation).

	.PARAMETER Branch
		The upstream branch. Defaults to the remote's HEAD branch, then master, then main.

	.PARAMETER DryRun
		Fetch and list exactly what the merge would take, decline and conflict on (git merge-tree),
		merging nothing.

	.PARAMETER RepositoryRoot
		The repository to merge into. Defaults to the repository this module was loaded from.

	.PARAMETER PassThru
		Return a result object (Status, Remote, Ref, Taken, Declined, Conflicts, CommitMessage).

	.EXAMPLE
		Merge-Upstreams winux
		Merges WinuX's default branch into this branch, leaving the merge staged for review.

	.EXAMPLE
		Merge-Upstreams foundation -DryRun
		Lists what a merge of Foundation would take and decline.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[string]$Branch,

		[switch]$DryRun,

		[string]$RepositoryRoot = (Get-RepositoryPath).Repo,

		[switch]$PassThru
	)

	$result = [pscustomobject]@{
		Status        = $null
		Remote        = $null
		Ref           = $null
		Taken         = [ordered]@{ own = @(); take = @(); mirror = @(); hallway = @() }
		Declined      = @()
		MirrorDrift   = @()
		Conflicts     = @()
		CommitMessage = $null
	}
	$finish = {
		param([string]$Status)
		$result.Status = $Status
		if ($PassThru) { return $result }
	}
	$root = $RepositoryRoot

	Write-LogTitle "Merge-Upstreams $Name"
	& git -C $root rev-parse --is-inside-work-tree *> $null
	if ($LASTEXITCODE -ne 0) {
		Write-LogError "[$root] is not a git repository!"
		return (& $finish 'Failed')
	}

	# The manifests of HEAD (every tracked upstream.conf that names an upstream) and the fork's settings.
	$readManifests = {
		param([string]$Revision)
		$found = @()
		$paths = @(& git -C $root -c core.quotepath=off ls-tree -r --name-only $Revision 2>$null |
				Where-Object { (Split-Path -Leaf $_) -ieq 'upstream.conf' })
		foreach ($path in $paths) {
			$text = (& git -C $root show "${Revision}:$path" 2>$null) -join "`n"
			$parsed = ConvertFrom-UpstreamManifest -Text $text
			if ($parsed.Name) { $found += $parsed }
		}
		return , $found
	}
	$headManifests = & $readManifests 'HEAD'
	$settingsPath = Join-Path -Path $root -ChildPath 'Git\upstreams.local.conf'
	$settings = if (Test-Path -LiteralPath $settingsPath) { ConvertFrom-UpstreamManifest -Text (Get-Content -LiteralPath $settingsPath -Raw) } else { $null }
	$known = @($headManifests | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)

	# The remote: by the manifest URL first, then by name. Nothing is ever written to git config.
	$remotes = @{}
	foreach ($remoteName in @(& git -C $root remote)) {
		$remotes[$remoteName] = (& git -C $root remote get-url $remoteName 2>$null) -join ''
	}
	$url = if ($known.Count -gt 0) { $known[0].Url } else { $null }
	$resolved = Resolve-UpstreamRemote -Name $Name -Url $url -Remotes $remotes
	if (-not $resolved.Remote) {
		if ($resolved.Fix) {
			Write-LogError "No remote for [$Name] - add it once, then merge again:"
			Write-LogList @($resolved.Fix)
		}
		else {
			Write-LogError "No manifest names [$Name] and no remote is called [$Name] - the known upstreams are: $(@($headManifests.Name) -join ', ')"
		}
		return (& $finish 'NeedsRemote')
	}
	$remote = $resolved.Remote
	$result.Remote = $remote

	if (-not $DryRun) {
		& git -C $root rev-parse -q --verify MERGE_HEAD *> $null
		if ($LASTEXITCODE -eq 0) {
			Write-LogError "A merge is already in progress - commit it or undo it with git merge --abort first!"
			return (& $finish 'Refused')
		}
		& git -C $root diff --quiet *> $null; $unstaged = $LASTEXITCODE
		& git -C $root diff --cached --quiet *> $null; $staged = $LASTEXITCODE
		if ($unstaged -ne 0 -or $staged -ne 0) {
			Write-LogError "Uncommitted changes to tracked files - commit or stash them first, so putting a path back cannot lose them!"
			return (& $finish 'Refused')
		}
	}

	& git -C $root fetch --no-tags -q $remote 2>$null
	if ($LASTEXITCODE -ne 0) {
		Write-LogError "git fetch $remote failed!"
		return (& $finish 'Failed')
	}
	$prefix = if ($known.Count -gt 0) { $known[0].TagPrefix } else { $null }
	if ($prefix) {
		& git -C $root fetch --no-tags -q $remote "+refs/tags/$prefix/*:refs/tags/$prefix/*" *> $null
	}

	if (-not $Branch) {
		$remoteHead = (& git -C $root symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>$null) -join ''
		if ($remoteHead) { $Branch = $remoteHead.Substring($remote.Length + 1) }
		foreach ($candidate in 'master', 'main') {
			if ($Branch) { break }
			& git -C $root show-ref --verify -q "refs/remotes/$remote/$candidate" *> $null
			if ($LASTEXITCODE -eq 0) { $Branch = $candidate }
		}
		if (-not $Branch) {
			Write-LogError "$remote has no HEAD, master or main branch - name one with -Branch!"
			return (& $finish 'Failed')
		}
	}
	$ref = "$remote/$Branch"
	$result.Ref = $ref
	& git -C $root show-ref --verify -q "refs/remotes/$ref" *> $null
	if ($LASTEXITCODE -ne 0) {
		Write-LogError "$remote has no branch [$Branch]!"
		return (& $finish 'Failed')
	}

	& git -C $root merge-base --is-ancestor $ref HEAD *> $null
	if ($LASTEXITCODE -eq 0) {
		Write-LogSuccess "Already up to date with $ref - nothing to merge!"
		return (& $finish 'UpToDate')
	}
	$base = (& git -C $root merge-base HEAD $ref 2>$null) -join ''
	if (-not $base) {
		Write-LogError "This branch shares no history with $ref - bridge it once, then merge again:"
		Write-LogList @("git merge -s ours --allow-unrelated-histories -m `"Bridge $Name as an upstream`" $ref")
		return (& $finish 'NeedsBridge')
	}

	# The rules: NAME's manifest as the upstream has it now (its rooms may have moved in this very
	# merge), every other upstream's as HEAD has it.
	$refManifests = & $readManifests $ref
	$upstream = @($refManifests | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
	$upstream = if ($upstream.Count -gt 0) { $upstream[0] } elseif ($known.Count -gt 0) { $known[0] } else { ConvertFrom-UpstreamManifest -Text "name $Name" }
	$others = @($headManifests | Where-Object { $_.Name -ne $Name })
	$names = @(@($headManifests.Name) + $Name | Sort-Object -Unique)
	$rootOwner = if ($settings -and $settings.RootOwner) { $settings.RootOwner } elseif ($names.Count -eq 1) { $Name } else { 'fork' }

	$changelog = $null
	if ($upstream.Changelog) {
		$changelogText = (& git -C $root show "${ref}:$($upstream.Changelog)" 2>$null) -join "`n"
		if ($changelogText -match '(?m)^## \[(\d+\.\d+\.\d+[^\]]*)\]') { $changelog = $Matches[1] }
	}
	$result.CommitMessage = "Merge $Name ${Branch}: $(if ($changelog) { $changelog } else { 'unreleased changes' })"

	$commitCount = (& git -C $root rev-list --count "$base..$ref") -join ''
	Write-LogStep "Merging $ref ($commitCount commits) - root owner: $rootOwner"

	if ($DryRun) {
		# git merge-tree makes the same merge the real run makes - the same merge machinery, the same
		# attributes and merge drivers - into a tree of its own, touching neither the index nor the
		# working tree. Comparing that tree with HEAD lists exactly what the real run would stage,
		# and the conflicted paths it would stop on, rather than everything the upstream changed.
		$mergeTree = @(& git -C $root -c core.quotepath=off merge-tree --write-tree --name-only --no-messages HEAD $ref 2>$null)
		if ($LASTEXITCODE -gt 1 -or $mergeTree.Count -eq 0 -or $mergeTree[0] -notmatch '^[0-9a-f]{40,64}$') {
			Write-LogError "git merge-tree could not compute the merge (it needs git 2.38 or newer)!"
			return (& $finish 'Failed')
		}
		$tree = $mergeTree[0]
		$changes = [ordered]@{}
		foreach ($line in @(& git -C $root -c core.quotepath=off diff --name-status --no-renames HEAD $tree)) {
			if (-not $line) { continue }
			$status, $path = $line -split "`t", 2
			$changes[$path] = $status
		}
		foreach ($path in @($mergeTree | Select-Object -Skip 1 | Where-Object { $_ })) { $changes[$path] = 'U' }

		foreach ($path in $changes.Keys) {
			$status = $changes[$path]
			$class = Resolve-UpstreamPathClass -Path $path -Upstream $upstream -Others $others -Settings $settings -RootOwner $rootOwner
			if ($class -eq 'declined') { $result.Declined += "$status $path"; continue }
			$result.Taken[$class] += "$status $path"
			if ($status -eq 'U') { $result.Conflicts += $path; continue }
			if ($class -eq 'mirror') {
				$theirs = (& git -C $root rev-parse -q --verify "${ref}:$path" 2>$null) -join ''
				$merged = (& git -C $root rev-parse -q --verify "${tree}:$path" 2>$null) -join ''
				if ($theirs -ne $merged) { $result.MirrorDrift += $path }
			}
		}
		Write-LogStep "Would take: $(@($result.Taken.Keys | ForEach-Object { "$($result.Taken[$_].Count) $_" }) -join ', ')"
		if ($result.Declined.Count -gt 0) {
			Write-LogStep "Would decline $($result.Declined.Count) (put back as this branch has them; git show ${ref}:PATH reads any):"
			Write-LogList $result.Declined
		}
		if ($result.Conflicts.Count -gt 0) {
			Write-LogWarning "Would stop on $($result.Conflicts.Count) conflict(s) to resolve:"
			Write-LogList $result.Conflicts
		}
		foreach ($path in $result.MirrorDrift) {
			Write-LogWarning "Mirror drift: $path - after the merge this branch's copy would differ from $Name's; the mirror contract says every upstream ships the same bytes"
		}
		Write-LogSuccess "Dry run - nothing was merged!"
		return (& $finish 'DryRun')
	}

	& git -C $root merge -q --no-commit --no-ff $ref *> $null
	& git -C $root rev-parse -q --verify MERGE_HEAD *> $null
	if ($LASTEXITCODE -ne 0) {
		Write-LogError "git merge $ref did not start (an untracked file in the way?) - run it by hand to see why!"
		return (& $finish 'Failed')
	}

	$candidates = @(@(& git -C $root -c core.quotepath=off diff --cached --name-only --no-renames HEAD) +
		@(& git -C $root -c core.quotepath=off diff --name-only --diff-filter=U) |
			Where-Object { $_ } | Sort-Object -Unique)
	foreach ($path in $candidates) {
		$class = Resolve-UpstreamPathClass -Path $path -Upstream $upstream -Others $others -Settings $settings -RootOwner $rootOwner
		if ($class -ne 'declined') { $result.Taken[$class] += $path; continue }

		$result.Declined += $path
		& git -C $root cat-file -e "HEAD:$path" *> $null
		if ($LASTEXITCODE -eq 0) {
			& git -C $root checkout -q HEAD -- $path *> $null
			continue
		}
		& git -C $root rm -q -f --cached -- $path *> $null
		$fullPath = Join-Path -Path $root -ChildPath $path
		if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Force }
		$folder = Split-Path -Parent $fullPath
		$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
		while ($folder -and [System.IO.Path]::GetFullPath($folder).TrimEnd('\', '/') -ne $rootFull -and
			(Test-Path -LiteralPath $folder) -and -not (Get-ChildItem -LiteralPath $folder -Force | Select-Object -First 1)) {
			Remove-Item -LiteralPath $folder -Force
			$folder = Split-Path -Parent $folder
		}
	}

	$takenSummary = @($result.Taken.Keys | ForEach-Object { "$($result.Taken[$_].Count) $_" }) -join ', '
	if ($result.Declined.Count -gt 0) {
		Write-LogStep "Declined $($result.Declined.Count) (put back as this branch has them; git show ${ref}:PATH reads any):"
		Write-LogList $result.Declined
	}

	$result.Conflicts = @(& git -C $root -c core.quotepath=off diff --name-only --diff-filter=U | Where-Object { $_ })
	if ($result.Conflicts.Count -gt 0) {
		Write-LogWarning "Conflicts left to resolve:"
		Write-LogList $result.Conflicts
		Write-LogStep "Resolve them and git add each, then commit - or undo everything with git merge --abort"
		return (& $finish 'Conflicts')
	}

	$current = (& git -C $root symbolic-ref -q --short HEAD 2>$null) -join ''
	Write-LogSuccess "Staged $ref - taken: $takenSummary. Review with git diff --cached (git merge --abort undoes it)."
	Write-LogStep "Commit message: $($result.CommitMessage)"
	if (-not $current -or $current -in 'master', 'main') {
		Write-LogStep "Give the merge a branch of its own (the staged merge comes along), commit, then push it for a pull request:"
		Write-LogList @("git switch -c merge-$Name", "git push -u origin merge-$Name")
	}
	else {
		Write-LogStep "Commit, then push it for a pull request:"
		Write-LogList @("git push -u origin $current")
	}
	return (& $finish 'Staged')
}
