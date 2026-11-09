#Requires -Modules Pester

<#
	The profile's deferred startup: the one PowerShell.OnIdle subscription that runs the queued
	stages after the first prompt. Its action once unregistered its own subscription, and when a
	second OnIdle was queued while the action ran, Unregister-Event waited for the executing action -
	itself - to finish, so the shell never read another key (a workspace tab that ignored typing and
	Ctrl+C). The real registration is lifted from the profile and run in a child shell with a timeout,
	so a regression shows up as a failed test, not a hung worker.
#>

BeforeAll {
	$profilePath = Join-Path (Get-RepositoryPath).PowerShell "Microsoft.PowerShell_profile.ps1"
	$tokens = $null
	$parseErrors = $null
	$profileAst = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$parseErrors)
	$script:ProfileAst = $profileAst

	$script:Registration = $profileAst.FindAll({
			param($node)
			$node -is [System.Management.Automation.Language.CommandAst] -and
			$node.GetCommandName() -eq 'Register-EngineEvent' -and
			$node.Extent.Text -match 'PowerShell\.OnIdle'
		}, $true) | Select-Object -First 1
}

Describe "Profile deferred startup (PowerShell.OnIdle)" -Tag 'Integration' {
	It "registers the OnIdle subscription with -MaxTriggerCount 1" {
		$script:Registration | Should -Not -BeNullOrEmpty
		$script:Registration.Extent.Text | Should -Match '-MaxTriggerCount\s+1\b'
	}

	It "never unregisters the subscription from inside its own action" {
		$unregisterCalls = $script:Registration.FindAll({
				param($node)
				$node -is [System.Management.Automation.Language.CommandAst] -and
				$node.GetCommandName() -eq 'Unregister-Event'
			}, $true)

		@($unregisterCalls).Count | Should -Be 0
	}

	It "queues the startup tasks of a new terminal: the prompt check first, then the TerminalOpen run" {
		# The stage that was "RepositoryUpdate". The prompt check is registered before the tasks
		# run because a task whose command asks for Administrator privileges stops the action it
		# runs in, and must not take the prompt check with it.
		$startupCalls = @($script:ProfileAst.FindAll({
					param($node)
					$node -is [System.Management.Automation.Language.CommandAst] -and
					$node.GetCommandName() -in 'Register-StartupTaskPromptCheck', 'Invoke-StartupTasks', 'Invoke-StartupRepositoryUpdate', 'Register-RepositoryUpdatePromptCheck'
				}, $true))

		@($startupCalls | ForEach-Object { $_.GetCommandName() }) | Should -Be @('Register-StartupTaskPromptCheck', 'Invoke-StartupTasks')
		$startupCalls[1].Extent.Text | Should -Match '-Trigger\s+TerminalOpen\b'
		$startupCalls[1].Extent.Text | Should -Match '-RedrawPrompt\b'

		$stageNames = @($script:ProfileAst.FindAll({
					param($node)
					$node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-StartupStage'
				}, $true) | ForEach-Object { $_.Extent.Text })
		@($stageNames | Where-Object { $_ -match '-Name\s+"StartupTasks"' }).Count | Should -Be 1
		@($stageNames | Where-Object { $_ -match '-Name\s+"RepositoryUpdate"' }).Count | Should -Be 0
	}

	It "runs the queue once and returns when another OnIdle arrives while it runs" {
		$registration = $script:Registration.Extent.Text -replace 'PowerShell\.OnIdle', 'WinuXTest.Idle'
		$childScript = @"
`$global:queueRuns = 0
`$global:WinuXDeferredStartup = [System.Collections.Generic.List[hashtable]]::new()
`$global:WinuXDeferredStartup.Add(@{ Name = 'Probe'; Action = { `$global:queueRuns++; `$null = New-Event -SourceIdentifier WinuXTest.Idle; Start-Sleep -Milliseconds 50 } })
$registration
`$null = New-Event -SourceIdentifier WinuXTest.Idle
for (`$i = 0; `$i -lt 10; `$i++) { Start-Sleep -Milliseconds 100 }
`$null = New-Event -SourceIdentifier WinuXTest.Idle
for (`$i = 0; `$i -lt 5; `$i++) { Start-Sleep -Milliseconds 100 }
"runs=`$global:queueRuns subscribers=`$(@(Get-EventSubscriber -Force | Where-Object SourceIdentifier -eq 'WinuXTest.Idle').Count)"
"@
		$scriptFile = Join-Path $TestDrive "deferred-startup-probe.ps1"
		$outputFile = Join-Path $TestDrive "deferred-startup-probe.txt"
		Set-Content -LiteralPath $scriptFile -Value $childScript -Encoding UTF8

		$pwsh = (Get-Process -Id $PID).Path
		$child = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-File', $scriptFile -RedirectStandardOutput $outputFile -WindowStyle Hidden -PassThru
		$exited = $child.WaitForExit(20000)
		if (-not $exited) { $child.Kill() }

		$exited | Should -BeTrue -Because "an action that waits on itself never returns"
		(Get-Content -LiteralPath $outputFile -Raw).Trim() | Should -Be 'runs=1 subscribers=0'
	}
}
