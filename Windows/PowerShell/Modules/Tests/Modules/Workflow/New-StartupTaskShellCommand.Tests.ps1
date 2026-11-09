#Requires -Modules Pester

BeforeAll {
	$script:SavedSkip = $env:WINUX_STARTUP_SKIP

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\New-StartupTaskShellCommand.ps1"

	# The produced text is read as PowerShell reads it, never run as a whole: it ends in `exit`
	# and calls Invoke-StartupTask. Fails the test when the text does not parse.
	function ConvertTo-TestShellAst {
		param([Parameter(Mandatory)][string]$Text)

		$tokens = $null
		$errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
		@($errors).Count | Should -Be 0 -Because "the produced text must be valid PowerShell"
		$ast
	}

	# The parameters the text hands to Invoke-StartupTask, decoded exactly as the new shell
	# decodes them: only the ConvertFrom-Json expression is evaluated.
	function Get-TestShellArguments {
		param([Parameter(Mandatory)][string]$Text)

		$assignment = @((ConvertTo-TestShellAst -Text $Text).EndBlock.Statements) | Where-Object {
			$_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$winuxStartupTaskArguments'
		} | Select-Object -First 1
		$assignment | Should -Not -BeNullOrEmpty -Because "the text must decode its parameters"

		& ([scriptblock]::Create($assignment.Right.Extent.Text))
	}
}

AfterAll {
	if ($null -eq $script:SavedSkip) { Remove-Item -Path Env:WINUX_STARTUP_SKIP -ErrorAction SilentlyContinue }
	else { $env:WINUX_STARTUP_SKIP = $script:SavedSkip }
}

Describe "New-StartupTaskShellCommand" {
	Context "the parameters of Invoke-StartupTask" {
		It "produces valid PowerShell: one string, its lines joined by line feeds" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -LoadProfile -TaskShell -ExitOn Succeeded

			@($text).Count | Should -Be 1
			$text | Should -BeOfType [string]
			$text.Contains("`r") | Should -BeFalse
			@((ConvertTo-TestShellAst -Text $text).EndBlock.Statements).Count | Should -BeGreaterThan 1
		}

		It "hands over exactly the parameters it was given" {
			$arguments = @{
				Name                 = 'MyTask'
				Command              = 'Open-Workspace MyWorkspace'
				Trigger              = 'SignIn'
				Requires             = @('Network')
				ConditionDefinitions = @{ Network = @{ Test = 'Test-Connection example.org -Count 1 -Quiet'; Timeout = 30 } }
				Window               = 'Current'
				DayStartHour         = 6
				IntervalHours        = 0.5
				Force                = $true
				ResultFile           = 'C:\Logs\.startup-task-MyTask.result'
			}

			$decoded = Get-TestShellArguments -Text (New-StartupTaskShellCommand -Arguments $arguments)

			(@($decoded.Keys) | Sort-Object) -join ',' | Should -Be ((@($arguments.Keys) | Sort-Object) -join ',')
			$decoded['Name'] | Should -BeExactly 'MyTask'
			$decoded['Command'] | Should -BeExactly 'Open-Workspace MyWorkspace'
			$decoded['Trigger'] | Should -BeExactly 'SignIn'
			$decoded['Window'] | Should -BeExactly 'Current'
			$decoded['DayStartHour'] | Should -Be 6
			$decoded['IntervalHours'] | Should -Be 0.5
			$decoded['Force'] | Should -BeOfType [bool]
			$decoded['Force'] | Should -BeTrue
			$decoded['ResultFile'] | Should -BeExactly 'C:\Logs\.startup-task-MyTask.result'
			@($decoded['Requires']).Count | Should -Be 1
			@($decoded['Requires'])[0] | Should -BeExactly 'Network'
		}

		It "hands the conditions over as hashtables, as Test-StartupCondition needs them" {
			$arguments = @{
				Name                 = 'MyTask'
				ConditionDefinitions = @{ Network = @{ Test = 'Test-Connection example.org -Count 1 -Quiet'; Timeout = 30 } }
			}

			$decoded = Get-TestShellArguments -Text (New-StartupTaskShellCommand -Arguments $arguments)

			($decoded -is [System.Collections.IDictionary]) | Should -BeTrue
			($decoded['ConditionDefinitions'] -is [System.Collections.IDictionary]) | Should -BeTrue
			($decoded['ConditionDefinitions']['Network'] -is [System.Collections.IDictionary]) | Should -BeTrue
			$decoded['ConditionDefinitions']['Network']['Test'] | Should -BeExactly 'Test-Connection example.org -Count 1 -Quiet'
			$decoded['ConditionDefinitions']['Network']['Timeout'] | Should -Be 30
		}

		It "keeps an empty list and a false switch" {
			$decoded = Get-TestShellArguments -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Requires = @(); Force = $false; ConditionDefinitions = @{} })

			$decoded.Contains('Requires') | Should -BeTrue
			@($decoded['Requires']).Count | Should -Be 0
			$decoded['Force'] | Should -BeOfType [bool]
			$decoded['Force'] | Should -BeFalse
			$decoded['ConditionDefinitions'].Count | Should -Be 0
		}

		It "carries a command with single quotes, double quotes, a dollar sign, a backtick and a line break unchanged" {
			$command = "Write-Host 'single' `"double`" `$env:USERPROFILE ``tick`nGet-Item -Path 'C:\Temp\a b' | Out-Null"

			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = $command } -TaskShell -ExitOn Succeeded
			$decoded = Get-TestShellArguments -Text $text

			$decoded['Command'] | Should -BeExactly $command
		}

		It "carries a command with letters outside ASCII unchanged, also through -Encoded" {
			$command = "Write-Host '" + [char]0x010D + [char]0x0161 + [char]0x017E + "'"

			$encoded = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = $command } -Encoded
			$text = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

			(Get-TestShellArguments -Text $text)['Command'] | Should -BeExactly $command
		}

		It "runs Invoke-StartupTask with the decoded parameters splatted, and nothing else" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' })

			$calls = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-StartupTask' }, $true))
			$calls.Count | Should -Be 1
			$calls[0].CommandElements.Count | Should -Be 2
			($calls[0].CommandElements[1] -is [System.Management.Automation.Language.VariableExpressionAst]) | Should -BeTrue
			$calls[0].CommandElements[1].Splatted | Should -BeTrue
			$calls[0].CommandElements[1].VariablePath.UserPath | Should -Be 'winuxStartupTaskArguments'

			# Decode, then run: two statements, and the command of the task is in neither as code.
			@($ast.EndBlock.Statements).Count | Should -Be 2
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Open-Workspace' }, $true)).Count | Should -Be 0
		}
	}

	Context "-LoadProfile" {
		AfterEach {
			Remove-Item -Path Env:WINUX_STARTUP_SKIP -ErrorAction SilentlyContinue
		}

		It "names the stages to skip, loads the profiles and clears the variable again, all before the work" {
			$text = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile -SkipStage Greeting, OhMyPosh
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements.Count | Should -Be 4

			# Only the first and the third statement run here: the second would load the real profiles.
			& ([scriptblock]::Create($statements[0].Extent.Text))
			$env:WINUX_STARTUP_SKIP | Should -Be 'Greeting,OhMyPosh'

			($statements[1] -is [System.Management.Automation.Language.ForEachStatementAst]) | Should -BeTrue
			$dotSourced = @($statements[1].FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq 'Dot' }, $true))
			$dotSourced.Count | Should -Be 1

			& ([scriptblock]::Create($statements[2].Extent.Text))
			$env:WINUX_STARTUP_SKIP | Should -BeNullOrEmpty

			$statements[3].Extent.Text | Should -BeExactly 'Invoke-StartupTasks -Trigger SignIn'
		}

		It "looks for every profile PowerShell itself would have loaded" {
			$text = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile
			$loop = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)[1]

			$profiles = @($loop.Condition.FindAll({ param($node) $node -is [System.Management.Automation.Language.MemberExpressionAst] }, $true) | ForEach-Object { $_.Member.Value })

			($profiles | Sort-Object) -join ',' | Should -Be 'AllUsersAllHosts,AllUsersCurrentHost,CurrentUserAllHosts,CurrentUserCurrentHost'
		}

		It "skips the interactive stages by default, the startup tasks of a new terminal among them" {
			$text = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			& ([scriptblock]::Create($statements[0].Extent.Text))
			$skipped = $env:WINUX_STARTUP_SKIP -split ','

			# Without StartupTasks in the list the runner's own shell would run the TerminalOpen tasks.
			$skipped | Should -Contain 'StartupTasks'
			$skipped | Should -Contain 'Greeting'
			$skipped | Should -Contain 'OhMyPosh'
		}

		It "drops empty stage names and survives a quote in one" {
			$text = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile -SkipStage "It's", '', 'Greeting'
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			& ([scriptblock]::Create($statements[0].Extent.Text))

			$env:WINUX_STARTUP_SKIP | Should -BeExactly "It's,Greeting"
		}

		It "adds the same prelude in front of an Invoke-StartupTask call" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -LoadProfile -SkipStage Greeting
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements.Count | Should -Be 5
			$statements[0].Left.Extent.Text | Should -Be '$env:WINUX_STARTUP_SKIP'
			($statements[1] -is [System.Management.Automation.Language.ForEachStatementAst]) | Should -BeTrue
			$statements[3].Left.Extent.Text | Should -Be '$winuxStartupTaskArguments'
			(Get-TestShellArguments -Text $text)['Name'] | Should -Be 'MyTask'
		}

		It "leaves the profile and the variable alone without the switch" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -SkipStage Greeting
			$ast = ConvertTo-TestShellAst -Text $text

			@($ast.EndBlock.Statements).Count | Should -Be 2
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)).Count | Should -Be 0
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'env:WINUX_STARTUP_SKIP' }, $true)).Count | Should -Be 0
		}
	}

	Context "-TaskShell" {
		It "marks the shell as a startup task's before the work starts" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -TaskShell
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements.Count | Should -Be 3
			$statements[0].Left.Extent.Text | Should -Be '$global:WinuXStartupTaskShell'
			$statements[0].Right.Extent.Text | Should -Be '$true'
			$statements[1].Left.Extent.Text | Should -Be '$winuxStartupTaskArguments'
		}

		It "marks the shell after the profile is loaded" {
			$text = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile -TaskShell
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements.Count | Should -Be 5
			$statements[3].Left.Extent.Text | Should -Be '$global:WinuXStartupTaskShell'
			$statements[4].Extent.Text | Should -BeExactly 'Invoke-StartupTasks -Trigger SignIn'
		}

		It "leaves the shell unmarked without the switch" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -LoadProfile -ExitAlways)

			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'global:WinuXStartupTaskShell' }, $true)).Count | Should -Be 0
		}
	}

	Context "-ExitOn and -ExitAlways" {
		It "never exits without either" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -LoadProfile -TaskShell)

			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 0
		}

		It "exits after the statuses named by -ExitOn, and after no other" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitOn Succeeded, NotDue
			$ast = ConvertTo-TestShellAst -Text $text
			$last = @($ast.EndBlock.Statements)[-1]

			# One exit, and only inside the condition at the very end.
			($last -is [System.Management.Automation.Language.IfStatementAst]) | Should -BeTrue
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 1
			@($last.Clauses[0].Item2.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 1
			$last.ElseClause | Should -BeNullOrEmpty

			# The condition itself is evaluated against the result the line before it stores.
			$condition = [scriptblock]::Create($last.Clauses[0].Item1.Extent.Text)
			foreach ($status in 'Succeeded', 'NotDue') {
				$winuxStartupTaskResult = [pscustomobject]@{ Status = $status }
				(& $condition) | Should -BeTrue -Because "the shell closes after [$status]"
			}
			foreach ($status in 'Failed', 'Skipped', 'HandedOff', 'TimedOut', 'AlreadyRunning') {
				$winuxStartupTaskResult = [pscustomobject]@{ Status = $status }
				(& $condition) | Should -BeFalse -Because "the shell stays open after [$status]"
			}
		}

		It "stays open when Invoke-StartupTask returned nothing" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitOn Succeeded
			$last = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)[-1]
			$condition = [scriptblock]::Create($last.Clauses[0].Item1.Extent.Text)

			# An inline run that was stopped (a refused elevation) returns no result at all.
			$winuxStartupTaskResult = $null
			[bool](& $condition) | Should -BeFalse
		}

		It "stores the result of Invoke-StartupTask in the variable the condition reads" {
			$text = New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitOn Succeeded
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements.Count | Should -Be 3
			$statements[1].Left.Extent.Text | Should -Be '$winuxStartupTaskResult'
			$read = @($statements[2].Clauses[0].Item1.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
			($read -join ',') | Should -Be 'winuxStartupTaskResult'
		}

		It "adds no condition for an -ExitOn of only empty names" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitOn '', '')

			@($ast.EndBlock.Statements).Count | Should -Be 2
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 0
		}

		It "exits whatever happened with -ExitAlways" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitAlways)
			$statements = @($ast.EndBlock.Statements)

			$statements.Count | Should -Be 3
			($statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
		}

		It "exits unconditionally when -ExitAlways and -ExitOn are both given" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Arguments @{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace' } -ExitOn Succeeded -ExitAlways)
			$statements = @($ast.EndBlock.Statements)

			($statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] }, $true)).Count | Should -Be 0
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 1
		}
	}

	Context "-Encoded" {
		It "returns the same text as UTF-16LE Base64, as pwsh -EncodedCommand takes it" {
			$arguments = [ordered]@{ Name = 'MyTask'; Command = "Write-Host 'done' `"now`""; Requires = @('Network'); Force = $true }

			$text = New-StartupTaskShellCommand -Arguments $arguments -LoadProfile -TaskShell -ExitAlways
			$encoded = New-StartupTaskShellCommand -Arguments $arguments -LoadProfile -TaskShell -ExitAlways -Encoded

			$encoded | Should -Not -Be $text
			[System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded)) | Should -BeExactly $text
		}

		It "encodes a -Command text the same way" {
			$encoded = New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger Wake' -ExitAlways -Encoded

			[System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded)) | Should -BeExactly "Invoke-StartupTasks -Trigger Wake`nexit"
		}
	}

	Context "-Command" {
		It "returns the command verbatim when nothing is added" {
			$command = "Write-Host 'single' `"double`" `$env:USERPROFILE`nGet-Item -Path 'C:\Temp\a b' | Out-Null"

			New-StartupTaskShellCommand -Command $command | Should -BeExactly $command
		}

		It "runs the command itself, not Invoke-StartupTask" {
			$ast = ConvertTo-TestShellAst -Text (New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -LoadProfile -ExitAlways)
			$statements = @($ast.EndBlock.Statements)

			$statements.Count | Should -Be 5
			$statements[3].Extent.Text | Should -BeExactly 'Invoke-StartupTasks -Trigger SignIn'
			($statements[4] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in 'Invoke-StartupTask', 'ConvertFrom-Json' }, $true)).Count | Should -Be 0
		}

		It "refuses -ExitOn, which needs the result of Invoke-StartupTask" {
			{ New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -ExitOn Succeeded } | Should -Throw
		}

		It "refuses -Command together with -Arguments" {
			{ New-StartupTaskShellCommand -Command 'Invoke-StartupTasks -Trigger SignIn' -Arguments @{ Name = 'MyTask' } } | Should -Throw
		}

		It "refuses an empty command" {
			{ New-StartupTaskShellCommand -Command '' } | Should -Throw
		}
	}
}
