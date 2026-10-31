#Requires -Modules Pester

# The repository policy matrix: AI\Hooks\ai-repository-policy.sh and the policy part of
# AI\Hooks\ai-ownership-guard.sh, run by Git's bash and fed Claude Code hook JSON directly (an agent
# refuses a dangerous command before the hook sees it, so a live session cannot test the hook).

BeforeDiscovery {
	$gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	$script:BashPath = ''
	if ($gitCommand) {
		# Git for Windows: <Git>\cmd\git.exe next to <Git>\bin\bash.exe. Never the bash.exe of
		# System32, which starts WSL.
		$candidate = Join-Path (Split-Path -Parent (Split-Path -Parent $gitCommand.Source)) 'bin\bash.exe'
		if (Test-Path -LiteralPath $candidate -PathType Leaf) { $script:BashPath = $candidate }
	}
	$script:NoBash = -not $script:BashPath
}

BeforeAll {
	$gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	$script:Bash = if ($gitCommand) { Join-Path (Split-Path -Parent (Split-Path -Parent $gitCommand.Source)) 'bin\bash.exe' } else { '' }
	$hooks = Join-Path (Get-RepositoryPath).Repo 'AI\Hooks'
	$script:PolicyHook = (Join-Path $hooks 'ai-repository-policy.sh').Replace('\', '/')
	$script:Guard = (Join-Path $hooks 'ai-ownership-guard.sh').Replace('\', '/')

	$script:Conf = (Join-Path $TestDrive 'ai-profile.conf')
	$script:Cache = (Join-Path $TestDrive 'tmp').Replace('\', '/')
	$script:FakeBin = Join-Path $TestDrive 'bin'
	New-Item -ItemType Directory -Path $script:FakeBin -Force | Out-Null

	# Two repositories with the same origin: one on a feature branch, one on the default branch.
	$script:Feature = (Join-Path $TestDrive 'feature').Replace('\', '/')
	$script:OnMaster = (Join-Path $TestDrive 'onmaster').Replace('\', '/')
	foreach ($pair in @(@($script:Feature, 'feature'), @($script:OnMaster, 'master'))) {
		git init -q -b $pair[1] $pair[0] 2>$null | Out-Null
		git -C $pair[0] remote add origin 'https://github.com/MyUser/MyProject.git' 2>$null | Out-Null
	}
	$script:Outside = (Join-Path $TestDrive 'outside').Replace('\', '/')
	New-Item -ItemType Directory -Path $script:Outside -Force | Out-Null

	function Set-PolicyConf([string[]]$Lines) {
		[IO.File]::WriteAllText($script:Conf, (($Lines + '') -join "`n"))
	}

	# The fake gh: `gh pr checks` answers as $State says (green, none, red).
	function Set-FakeGh([string]$State) {
		$body = switch ($State) {
			'green' { 'exit 0' }
			'none' { 'echo "no checks reported on the ''feature'' branch" >&2; exit 1' }
			default { 'echo "some checks were not successful" >&2; exit 1' }
		}
		[IO.File]::WriteAllText((Join-Path $script:FakeBin 'gh'), "#!/usr/bin/env bash`n$body`n")
	}

	# Runs a hook on one hook input and returns its decision: allow, or the deny/block reason.
	function Invoke-PolicyHook {
		param(
			[string]$Command,
			[string]$Tool = 'Bash',
			[string]$Cwd = $script:Feature,
			[string]$Hook = $script:PolicyHook,
			[string]$HookEvent = '',
			[string]$Unattended = ''
		)
		$hookInput = @{
			session_id = [guid]::NewGuid().ToString()
			cwd        = $Cwd
			tool_name  = $Tool
			tool_input = @{ command = $Command }
		} | ConvertTo-Json -Compress -EscapeHandling Default
		$saved = @{ Conf = $env:AI_PROFILE_CONF; Tmp = $env:TMPDIR; Unattended = $env:AI_UNATTENDED; Path = $env:PATH }
		try {
			$env:AI_PROFILE_CONF = $script:Conf.Replace('\', '/')
			$env:TMPDIR = $script:Cache
			$env:AI_UNATTENDED = $Unattended
			$env:PATH = "$($script:FakeBin);$($env:PATH)"
			$arguments = @($Hook)
			if ($HookEvent) { $arguments += $HookEvent }
			$output = ($hookInput | & $script:Bash @arguments) -join "`n"
		}
		finally {
			$env:AI_PROFILE_CONF = $saved.Conf
			$env:TMPDIR = $saved.Tmp
			$env:AI_UNATTENDED = $saved.Unattended
			$env:PATH = $saved.Path
		}
		if (-not $output) { return 'allow' }
		$decision = $output | ConvertFrom-Json -AsHashtable
		if ($decision.hookSpecificOutput) { return "deny: $($decision.hookSpecificOutput.permissionDecisionReason)" }
		return "block: $($decision.reason)"
	}
}

Describe "ai-repository-policy.sh" -Tag 'Integration' -Skip:$script:NoBash {
	BeforeEach {
		Set-FakeGh 'red'
	}

	Context "the always-denied list, at every level that runs commands" -ForEach @(
		@{ Level = 'autonomous' }
		@{ Level = 'branch' }
		@{ Level = 'draft' }
	) {
		BeforeEach {
			Set-PolicyConf @('profile Personal', "default-policy $Level")
		}

		It "<Level>: denies <Name>" -ForEach @(
			@{ Name = 'a force push'; Command = 'git push --force origin feature'; Reason = '*force pushes*' }
			@{ Name = 'a force-with-lease push'; Command = 'git push --force-with-lease'; Reason = '*force pushes*' }
			@{ Name = 'a -f push on a later line'; Command = "git status`ngit push -f"; Reason = '*force pushes*' }
			@{ Name = 'a +refspec push'; Command = 'git push origin +feature'; Reason = '*force pushes*' }
			@{ Name = 'a push to master'; Command = 'git push origin master'; Reason = '*default branch*' }
			@{ Name = 'a push to HEAD:main'; Command = 'git push origin HEAD:main'; Reason = '*default branch*' }
			@{ Name = 'a branch deletion'; Command = 'git branch -D old'; Reason = '*deleting branches*' }
			@{ Name = 'a remote branch deletion'; Command = 'git push origin --delete old'; Reason = '*deleting branches*' }
			@{ Name = 'a :branch push'; Command = 'git push origin :old'; Reason = '*deleting branches*' }
			@{ Name = 'a remote change'; Command = 'git remote set-url origin https://example.com/x.git'; Reason = '*remotes*' }
			@{ Name = 'an upstream change'; Command = 'git branch -u origin/master'; Reason = '*upstream*' }
			@{ Name = 'a tracking branch'; Command = 'git switch --track origin/master'; Reason = '*upstream*' }
			@{ Name = 'a branch cut from a remote branch without --no-track'; Command = 'git switch -c topic origin/master'; Reason = '*--no-track*' }
			@{ Name = 'a git config write'; Command = 'git config user.name Someone'; Reason = '*git configuration*' }
			@{ Name = 'a force push inside bash -c'; Command = 'bash -c "git push --force"'; Reason = '*force pushes*' }
			@{ Name = 'a force push in a heredoc fed to bash'; Command = "bash <<'EOF'`ngit push --force`nEOF"; Reason = '*force pushes*' }
			@{ Name = 'a force push from PowerShell'; Command = 'git push --force'; Tool = 'PowerShell'; Reason = '*force pushes*' }
		) {
			$tool = if ($Tool) { $Tool } else { 'Bash' }
			Invoke-PolicyHook -Command $Command -Tool $tool | Should -BeLike "deny: *$Reason"
		}

		It "<Level>: allows <Name>" -ForEach @(
			@{ Name = 'a commit'; Command = 'git add -A && git commit -m "Add the thing"' }
			@{ Name = 'a commit message that mentions git configuration'; Command = 'git commit -m "Document the Foundation configuration reference"' }
			@{ Name = 'a commit message that mentions a force push'; Command = 'git commit -m "Explain why git push --force is denied"' }
			@{ Name = 'a heredoc commit message'; Command = "git commit -m `"`$(cat <<'EOF'`nWhy git config and git push --force are denied`n`nEOF`n)`"" }
			@{ Name = 'a -F - heredoc commit message'; Command = "git commit -F - <<'EOF'`nNever git push origin master`nEOF" }
			@{ Name = 'a PowerShell here-string commit message'; Command = "git commit -m @'`nNever git config --global or git push --force`n'@"; Tool = 'PowerShell' }
			@{ Name = 'a feature branch push'; Command = 'git push -u origin feature' }
			@{ Name = 'a branch cut with --no-track'; Command = 'git switch -c topic --no-track origin/master' }
			@{ Name = 'a git config read'; Command = 'git config --get user.name' }
			@{ Name = 'a git config list'; Command = 'git config --list' }
			@{ Name = 'a read-only command'; Command = 'git status && git log --oneline -5' }
		) {
			$tool = if ($Tool) { $Tool } else { 'Bash' }
			Invoke-PolicyHook -Command $Command -Tool $tool | Should -Be 'allow'
		}

		It "<Level>: allows the file tools" {
			Invoke-PolicyHook -Command '' -Tool 'Edit' | Should -Be 'allow'
			Invoke-PolicyHook -Command '' -Tool 'Write' | Should -Be 'allow'
		}
	}

	It "denies a plain push while the default branch is checked out, and allows naming a feature branch" {
		Set-PolicyConf @('profile Personal', 'default-policy branch')

		Invoke-PolicyHook -Command 'git push' -Cwd $script:OnMaster | Should -BeLike 'deny: *checked-out branch is the default branch*'
		Invoke-PolicyHook -Command 'git push origin feature' -Cwd $script:OnMaster | Should -Be 'allow'
	}

	Context "pull requests per level" {
		It "autonomous: <Name>" -ForEach @(
			@{ Name = 'merges when every check passed'; Checks = 'green'; Lines = @(); Expected = 'allow' }
			@{ Name = 'refuses a merge with a failing check'; Checks = 'red'; Lines = @(); Expected = 'deny: *every CI check*' }
			@{ Name = 'refuses a merge with no check reported'; Checks = 'none'; Lines = @(); Expected = 'deny: *every CI check*' }
			@{ Name = 'merges with no check reported in a merge-without-checks repository'; Checks = 'none'; Lines = @('merge-without-checks github.com/myuser/*'); Expected = 'allow' }
			@{ Name = 'still refuses a failing check in a merge-without-checks repository'; Checks = 'red'; Lines = @('merge-without-checks github.com/myuser/myproject'); Expected = 'deny: *every CI check*' }
		) {
			Set-PolicyConf (@('profile Personal', 'default-policy autonomous') + $Lines)
			Set-FakeGh $Checks

			Invoke-PolicyHook -Command 'gh pr merge 12 --squash' | Should -BeLike $Expected
		}

		It "autonomous: allows opening and readying a pull request" {
			Set-PolicyConf @('profile Personal', 'default-policy autonomous')

			Invoke-PolicyHook -Command 'gh pr create --title "Add it" --body "Body"' | Should -Be 'allow'
			Invoke-PolicyHook -Command 'gh pr ready 12' | Should -Be 'allow'
		}

		It "branch: opens and readies a pull request, never merges, even with green checks" {
			Set-PolicyConf @('profile Personal', 'default-policy branch')
			Set-FakeGh 'green'

			Invoke-PolicyHook -Command 'gh pr create --title "Add it" --body "Body"' | Should -Be 'allow'
			Invoke-PolicyHook -Command 'gh pr ready 12' | Should -Be 'allow'
			Invoke-PolicyHook -Command 'gh pr merge 12' | Should -BeLike 'deny: *autonomous repository*'
		}

		It "draft: opens draft pull requests only, never readies or merges" {
			Set-PolicyConf @('profile Personal', 'default-policy draft')
			Set-FakeGh 'green'

			Invoke-PolicyHook -Command 'gh pr create --draft --title "Add it"' | Should -Be 'allow'
			Invoke-PolicyHook -Command 'gh pr create --title "Add it"' | Should -BeLike 'deny: *--draft*'
			Invoke-PolicyHook -Command 'gh pr create --title "Add it" --body "Mention --draft here"' | Should -BeLike 'deny: *--draft*' -Because "a --draft in the body is prose, not the flag"
			Invoke-PolicyHook -Command 'gh pr ready 12' | Should -BeLike 'deny: *'
			Invoke-PolicyHook -Command 'gh pr merge 12' | Should -BeLike 'deny: *'
		}
	}

	Context "readonly and blocked" {
		It "<Level>: denies the <Tool> tool" -ForEach @(
			@{ Level = 'readonly'; Tool = 'Bash' }
			@{ Level = 'readonly'; Tool = 'PowerShell' }
			@{ Level = 'readonly'; Tool = 'Edit' }
			@{ Level = 'readonly'; Tool = 'Write' }
			@{ Level = 'readonly'; Tool = 'MultiEdit' }
			@{ Level = 'readonly'; Tool = 'NotebookEdit' }
			@{ Level = 'blocked'; Tool = 'Bash' }
			@{ Level = 'blocked'; Tool = 'Edit' }
		) {
			Set-PolicyConf @('profile Personal', "default-policy $Level")

			Invoke-PolicyHook -Command 'ls' -Tool $Tool | Should -BeLike "deny: *, $Level)*"
		}

		It "readonly: allows the reading tools" {
			Set-PolicyConf @('profile Personal', 'default-policy readonly')

			Invoke-PolicyHook -Command '' -Tool 'Read' | Should -Be 'allow'
			Invoke-PolicyHook -Command '' -Tool 'Grep' | Should -Be 'allow'
		}
	}

	Context "the level of a repository" {
		It "takes the last matching line, autonomous lines included, over the default" {
			Set-PolicyConf @('profile Personal', 'default-policy readonly', 'policy branch github.com/myuser/*', 'autonomous github.com/MyUser/MyProject')
			Set-FakeGh 'green'

			Invoke-PolicyHook -Command 'gh pr merge 12' | Should -Be 'allow'
		}

		It "lets a later, less trusting line win" {
			Set-PolicyConf @('profile Personal', 'policy autonomous github.com/myuser/*', 'policy readonly github.com/myuser/myproject')

			Invoke-PolicyHook -Command 'ls' | Should -BeLike 'deny: *readonly)*'
		}

		It "reads several patterns on one line" {
			Set-PolicyConf @('profile Personal', 'default-policy readonly', 'policy branch github.com/other/* github.com/myuser/myproject')

			Invoke-PolicyHook -Command 'ls' | Should -Be 'allow'
		}

		It "ignores a line naming an unknown level" {
			Set-PolicyConf @('profile Personal', 'default-policy readonly', 'policy autonomus github.com/myuser/*')

			Invoke-PolicyHook -Command 'ls' | Should -BeLike 'deny: *readonly)*'
		}

		It "fails closed to readonly for a default-policy that is not a level" {
			Set-PolicyConf @('profile Personal', 'default-policy autonomus')

			Invoke-PolicyHook -Command 'ls' -Cwd $script:Outside | Should -BeLike 'deny: *readonly)*'
		}

		It "is branch with no default-policy line, also outside any repository" {
			Set-PolicyConf @('profile Personal')

			Invoke-PolicyHook -Command 'gh pr merge 12' -Cwd $script:Outside | Should -BeLike 'deny: *(no origin, branch)*'
		}

		It "allows everything with profiles off" {
			Set-PolicyConf @()

			Invoke-PolicyHook -Command 'git push --force' | Should -Be 'allow'
		}
	}
}

Describe "ai-ownership-guard.sh, repository policy" -Tag 'Integration' -Skip:$script:NoBash {
	It "<Name>" -ForEach @(
		@{ Name = 'refuses the prompt in a blocked repository'; Lines = @('policy blocked github.com/myuser/*'); Unattended = ''; Expected = 'block: *is blocked*' }
		@{ Name = 'allows an attended session at draft'; Lines = @('policy draft github.com/myuser/*'); Unattended = ''; Expected = 'allow' }
		@{ Name = 'refuses an unattended run at draft'; Lines = @('policy draft github.com/myuser/*'); Unattended = '1'; Expected = 'block: *unattended runs need*' }
		@{ Name = 'refuses an unattended run at readonly'; Lines = @('default-policy readonly'); Unattended = 'on'; Expected = 'block: *unattended runs need*' }
		@{ Name = 'allows an unattended run at branch'; Lines = @(); Unattended = 'true'; Expected = 'allow' }
		@{ Name = 'allows an unattended run at autonomous'; Lines = @('autonomous github.com/myuser/myproject'); Unattended = 'yes'; Expected = 'allow' }
		@{ Name = 'refuses an unattended run when the profile has unattended off'; Lines = @(); Unattended = '1'; Off = $true; Expected = 'block: *unattended runs are off*' }
	) {
		$unattendedLine = if ($Off) { 'unattended off' } else { 'unattended on' }
		Set-PolicyConf (@('profile Personal', 'default-owner Personal', $unattendedLine) + $Lines)

		Invoke-PolicyHook -Command '' -Hook $script:Guard -HookEvent 'UserPromptSubmit' -Unattended $Unattended | Should -BeLike $Expected
	}

	It "refuses every tool call in a blocked repository" {
		Set-PolicyConf @('profile Personal', 'default-owner Personal', 'policy blocked github.com/myuser/myproject')

		Invoke-PolicyHook -Command '' -Tool 'Read' -Hook $script:Guard -HookEvent 'PreToolUse' | Should -BeLike 'deny: *is blocked*'
	}

	It "keeps refusing a repository another profile owns, whatever its level" {
		Set-PolicyConf @('profile Personal', 'default-owner Personal', 'owns Work github.com/myuser/*', 'autonomous github.com/myuser/myproject')

		Invoke-PolicyHook -Command '' -Hook $script:Guard -HookEvent 'UserPromptSubmit' | Should -BeLike 'block: *belongs to the Work AI profile*'
	}
}
