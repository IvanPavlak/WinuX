<#
	.SYNOPSIS
		Shared real-git fixtures for the repository-update data-safety tests.

	.DESCRIPTION
		Dot-source this file from the BeforeAll of each Update-Repository.DataSafety.*.Tests.ps1 file
		(that also loads the code under test), then call Initialize-RepositoryDataSafety once; call
		Set-RepositoryDataSafetyDefaults in BeforeEach and Restore-RepositoryDataSafety in AfterAll.

		The data-safety tests run the real update code against real git, because two of the losses
		they guard against were git itself behaving unexpectedly (a fast-forward silently overwriting
		an ignored file; `git stash push` reporting success without creating a stash), which a mocked
		git cannot reveal. Every test builds its own throwaway origin and clone in TestDrive,
		fingerprints the repository (the bytes of every file - tracked, untracked and ignored - plus
		every commit, stash and branch), runs the real code, fingerprints again, and
		Get-LossViolations requires that:

		  1. every changed, untracked or ignored file still has its exact content, or that content is
		     recoverable from a stash that still exists;
		  2. every commit reachable before is still reachable;
		  3. none of the user's own stashes was applied or dropped;
		  4. a new stash is left behind only when the outcome says so;
		  5. no branch moved backward or sideways;
		  6. HEAD is still on the same branch (or the same detached commit).

		Speed: the scenarios are split over several files so the harness runs them on parallel
		workers; the origin is built once per file as a template and cloned per test (about 0.3 s
		instead of about 1 s); and a fingerprint hashes every file with ONE git process
		(`hash-object --stdin-paths`) instead of one per file - identical object ids, including for
		files whose line endings git converts.

		This file is NOT named *.Tests.ps1 on purpose: the harness discovers only that pattern, so
		this stays a helper and never becomes a test target.
#>

# The code under test, loaded at the top level so that dot-sourcing this file from a BeforeAll
# puts it exactly where the tests and Pester's mocks look for it.
$DataSafetyModuleRoot = (Get-RepositoryPath).Modules
foreach ($function in 'Get-ConfigSetting', 'Initialize-Directory', 'Get-RepositoryName') {
	. "$DataSafetyModuleRoot\Helper\Functions\$function.ps1"
}
foreach ($function in 'Resolve-RepositoryDefaultBranch', 'Update-RepositoryDefaultBranch', 'Restore-RepositoryStash', 'Update-Repository',
	'Format-RepositoryUpdateResult', 'Update-Repositories', 'Resolve-RepositoryTargets', 'Initialize-Repository',
	'Test-RepositoryUpdateStampFresh', 'Invoke-StartupRepositoryUpdate') {
	. "$DataSafetyModuleRoot\Git\Functions\$function.ps1"
}
. "$DataSafetyModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"

function Initialize-RepositoryDataSafety {
	<#
	.SYNOPSIS
		Saves the global state the tests change, sets a git identity, and builds the template
		origin every test clones. Call once from BeforeAll, after dot-sourcing this file.
	#>
	$script:DataSafetySaved = @{ Configuration = $global:Configuration; LoggingState = $global:LoggingState; MachineType = $global:MachineType; Env = @{} }
	foreach ($name in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL') {
		$script:DataSafetySaved.Env[$name] = [Environment]::GetEnvironmentVariable($name)
		[Environment]::SetEnvironmentVariable($name, $(if ($name -like '*EMAIL') { 'test@example.com' } else { 'Test' }))
	}
	$script:Git = @('-c', 'init.defaultBranch=master', '-c', 'protocol.file.allow=always', '-c', 'advice.detachedHead=false')

	# The template: origin.git with master (a.txt, b.txt, dir/c.txt, .gitignore, tag v1) and feature
	# (f.txt). Built once; New-TestOrigin clones it.
	$template = Join-Path $TestDrive 'template'
	New-Item -ItemType Directory -Path $template -Force | Out-Null
	git @script:Git init --quiet --bare "$template\origin.git"
	git @script:Git clone --quiet "$template\origin.git" "$template\seed" 2>$null
	Set-Content "$template\seed\a.txt" "a1`na2`na3"
	Set-Content "$template\seed\b.txt" "b1`nb2`nb3"
	New-Item -ItemType Directory "$template\seed\dir" -Force | Out-Null
	Set-Content "$template\seed\dir\c.txt" "c1"
	Set-Content "$template\seed\.gitignore" "*.log`nlocal.json`nbin/"
	git -C "$template\seed" add -A; git -C "$template\seed" commit --quiet -m one; git -C "$template\seed" tag v1
	git -C "$template\seed" push --quiet origin master --tags 2>$null
	git -C "$template\seed" switch --quiet -c feature
	Set-Content "$template\seed\f.txt" "f1"
	git -C "$template\seed" add -A; git -C "$template\seed" commit --quiet -m f1
	git -C "$template\seed" push --quiet -u origin feature 2>$null
	$script:TemplateOrigin = "$template\origin.git"
}

function Restore-RepositoryDataSafety {
	<# .SYNOPSIS Puts back the global state and git identity Initialize-RepositoryDataSafety changed. #>
	$global:Configuration = $script:DataSafetySaved.Configuration
	$global:LoggingState = $script:DataSafetySaved.LoggingState
	$global:MachineType = $script:DataSafetySaved.MachineType
	# A variable that was not set is removed again, not set to "": PowerShell passes $null to a .NET
	# string parameter as an empty string, and an empty GIT_AUTHOR_NAME overrides every user.name,
	# which made every later real-git test in the same worker fail to commit.
	foreach ($name in $script:DataSafetySaved.Env.Keys) {
		if ($null -eq $script:DataSafetySaved.Env[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
		else { [Environment]::SetEnvironmentVariable($name, $script:DataSafetySaved.Env[$name]) }
	}
}

function Set-RepositoryDataSafetyDefaults {
	<# .SYNOPSIS The configuration and logging state every test starts from. #>
	$global:Configuration = @{ BootstrapConfig = @{}; RepositoryGroups = @(); RepositoryUpdate = @{ IncludeDefaultBranch = $true; DefaultBranch = ''; Startup = @{ Enabled = $true } } }
	$global:LoggingState = @{ Level = 'Quiet'; Colors = @{}; FileLogging = $false; LogsDir = (Join-Path $TestDrive 'logs') }
	$global:MachineType = 'Test'
}

function New-TestOrigin([string]$Name) {
	<# .SYNOPSIS A fresh origin.git cloned from the template, plus the "seed" clone that plays the other developer pushing upstream. #>
	$dir = Join-Path $TestDrive $Name
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
	git @script:Git clone --quiet --bare --local $script:TemplateOrigin "$dir\origin.git" 2>$null
	git @script:Git clone --quiet "$dir\origin.git" "$dir\seed" 2>$null
	return $dir
}

function New-TestClone([string]$Dir, [string]$Name = 'work') {
	git @script:Git clone --quiet "$Dir\origin.git" "$Dir\$Name" 2>$null
	return "$Dir\$Name"
}

function Push-TestUpstream([string]$Dir, [string]$Branch, [scriptblock]$Change) {
	git -C "$Dir\seed" switch --quiet $Branch 2>$null
	git -C "$Dir\seed" pull --quiet --ff-only 2>$null
	Push-Location "$Dir\seed"
	try { & $Change } finally { Pop-Location }
	git -C "$Dir\seed" add -A; git -C "$Dir\seed" commit --quiet -m "upstream change"
	git -C "$Dir\seed" push --quiet origin $Branch 2>$null
	git -C "$Dir\seed" switch --quiet master
}

function Add-TestCommit([string]$Repo, [string]$File, [string]$Content, [string]$Message = 'local') {
	Set-Content (Join-Path $Repo $File) $Content
	git -C $Repo add -A
	git -C $Repo commit --quiet -m $Message
}

function Get-RepoFingerprint([string]$Repo) {
	$files = @{}; $blobs = @{}
	if (Test-Path $Repo) {
		$entries = @(Get-ChildItem -LiteralPath $Repo -Recurse -Force -File -ErrorAction SilentlyContinue |
				Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' })
		if ($entries.Count -gt 0) {
			# One git process for every file; ids come back in input order.
			$ids = @($entries.FullName | git -C $Repo hash-object --stdin-paths 2>$null)
			for ($i = 0; $i -lt $entries.Count; $i++) {
				$relative = $entries[$i].FullName.Substring($Repo.Length + 1).Replace('\', '/')
				$files[$relative] = (Get-FileHash -LiteralPath $entries[$i].FullName -Algorithm SHA256).Hash
				$blobs[$relative] = "$($ids[$i])"
			}
		}
	}
	$isRepo = (git -C $Repo rev-parse --is-inside-work-tree 2>$null) -eq 'true'
	$headBlobs = @{}; $index = @{}; $branches = @{}
	if ($isRepo) {
		git -C $Repo ls-tree -r HEAD 2>$null | ForEach-Object { $parts = $_ -split "`t", 2; $headBlobs[$parts[1]] = ($parts[0] -split ' ')[2] }
		git -C $Repo ls-files -s 2>$null | ForEach-Object { $parts = $_ -split "`t", 2; $index[$parts[1]] = ($parts[0] -split ' ')[1] }
		git -C $Repo for-each-ref --format='%(refname:short) %(objectname)' refs/heads 2>$null | ForEach-Object { $parts = $_ -split ' '; $branches[$parts[0]] = $parts[1] }
	}
	[pscustomobject]@{
		Files     = $files
		Blobs     = $blobs
		HeadBlobs = $headBlobs
		Index     = $index
		Branches  = $branches
		Commits   = @(if ($isRepo) { git -C $Repo rev-list --all 2>$null })
		Stashes   = @(if ($isRepo) { git -C $Repo stash list --format=%H 2>$null })
		HeadRef   = $(if ($isRepo) { "$(git -C $Repo symbolic-ref --quiet HEAD 2>$null)|$(git -C $Repo rev-parse HEAD 2>$null)" })
		IsRepo    = $isRepo
	}
}

function Get-StashBlobSet([string]$Repo) {
	$set = [System.Collections.Generic.HashSet[string]]::new()
	foreach ($stash in @(git -C $Repo stash list --format=%H 2>$null)) {
		foreach ($commit in @($stash, "$stash^2", "$stash^3")) {
			git -C $Repo ls-tree -r $commit 2>$null | ForEach-Object { [void]$set.Add((($_ -split "`t")[0] -split ' ')[2]) }
		}
	}
	return , $set
}

function Get-LossViolations([string]$Repo, $Before, $After, [string]$Outcome, [switch]$AnyOutcome, [string[]]$ExpectedForeignStash = @()) {
	<#
	.SYNOPSIS
		Every way local work could have been lost between two fingerprints; empty means nothing was.
		-AnyOutcome is for runs over several repositories, where a kept stash is legitimate and
		rule 1 already proves what it holds.
	#>
	$violations = [System.Collections.Generic.List[string]]::new()
	$stashBlobs = $null
	foreach ($path in $Before.Files.Keys) {
		$userOwned = (-not $Before.HeadBlobs.ContainsKey($path)) -or ($Before.HeadBlobs[$path] -ne $Before.Blobs[$path])
		if (-not $userOwned -or $After.Files[$path] -eq $Before.Files[$path]) { continue }
		if ($null -eq $stashBlobs) { $stashBlobs = Get-StashBlobSet $Repo }
		if ($Before.Blobs[$path] -and $stashBlobs.Contains($Before.Blobs[$path])) { continue }
		$violations.Add("lost content: $path")
	}
	if ($Before.IsRepo) {
		$afterCommits = [System.Collections.Generic.HashSet[string]]::new([string[]]$After.Commits)
		foreach ($commit in $Before.Commits) { if (-not $afterCommits.Contains($commit)) { $violations.Add("lost commit: $commit") } }
	}
	foreach ($stash in $Before.Stashes) { if ($After.Stashes -notcontains $stash) { $violations.Add("user stash applied or dropped: $stash") } }
	$newStashes = @($After.Stashes | Where-Object { $Before.Stashes -notcontains $_ } |
			Where-Object { $subject = git -C $Repo log -1 --format=%s $_ 2>$null; -not ($ExpectedForeignStash | Where-Object { $subject -match $_ }) })
	if ($newStashes.Count -gt 0 -and -not $AnyOutcome -and $Outcome -notin @('StashConflict', 'StashFailed', 'Error')) {
		$violations.Add("stash left behind although the outcome is $Outcome")
	}
	foreach ($branch in $Before.Branches.Keys) {
		$old = $Before.Branches[$branch]; $new = $After.Branches[$branch]
		if (-not $new) { $violations.Add("branch deleted: $branch"); continue }
		if ($old -ne $new) {
			git -C $Repo merge-base --is-ancestor $old $new 2>$null
			if ($LASTEXITCODE -ne 0) { $violations.Add("branch moved backward or sideways: $branch") }
		}
	}
	$beforeRef = ($Before.HeadRef -split '\|')[0]; $afterRef = ($After.HeadRef -split '\|')[0]
	if ($beforeRef -ne $afterRef) { $violations.Add("HEAD switched from '$beforeRef' to '$afterRef'") }
	elseif (-not $beforeRef -and $Before.HeadRef -ne $After.HeadRef) { $violations.Add("detached HEAD moved") }
	return , $violations
}

function Invoke-CheckedUpdate([string]$Repo, [string]$LocalPath = $Repo, [switch]$Loud, [string[]]$ExpectedForeignStash = @()) {
	<# .SYNOPSIS Runs one Update-Repository with fingerprints around it and checks every rule. #>
	$before = Get-RepoFingerprint $Repo
	$result = Update-Repository -Name 'work' -LocalPath $LocalPath -IncludeDefaultBranch -Quiet:(-not $Loud)
	$after = Get-RepoFingerprint $Repo
	$violations = Get-LossViolations -Repo $Repo -Before $before -After $after -Outcome $result.Outcome -ExpectedForeignStash $ExpectedForeignStash
	[pscustomobject]@{ Result = $result; Before = $before; After = $after; Violations = @($violations) }
}
