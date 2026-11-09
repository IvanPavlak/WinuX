#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Start-StartupTaskShell.ps1"
	# The real builder: what this function hands to the new shell is its text, so the tests read
	# that text instead of trusting a mock's parameters.
	. "$ModuleRoot\Workflow\Functions\New-StartupTaskShellCommand.ps1"

	# The command text is read as PowerShell reads it, never run: it calls Invoke-StartupTask and
	# may end in `exit`. Fails the test when the text does not parse.
	function ConvertTo-TestShellAst {
		param([Parameter(Mandatory)][string]$Text)

		$tokens = $null
		$errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
		@($errors).Count | Should -Be 0 -Because "the shell's command must be valid PowerShell"
		$ast
	}

	# The parameters the text hands to Invoke-StartupTask: only its ConvertFrom-Json expression runs.
	function Get-TestShellArguments {
		param([Parameter(Mandatory)][string]$Text)

		$assignment = @((ConvertTo-TestShellAst -Text $Text).EndBlock.Statements) | Where-Object {
			$_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$winuxStartupTaskArguments'
		} | Select-Object -First 1
		$assignment | Should -Not -BeNullOrEmpty -Because "the shell must be handed the task's parameters"

		& ([scriptblock]::Create($assignment.Right.Extent.Text))
	}

	# Whether the text marks its shell as a startup task's ($global:WinuXStartupTaskShell).
	function Test-TestShellMarked {
		param([Parameter(Mandatory)][string]$Text)

		@((ConvertTo-TestShellAst -Text $Text).FindAll({
					param($node)
					$node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$global:WinuXStartupTaskShell'
				}, $true)).Count -gt 0
	}

	# The text behind `pwsh -EncodedCommand <Base64>` in an argument list.
	function Get-TestEncodedText {
		param([Parameter(Mandatory)][string[]]$ArgumentList)

		$index = [array]::IndexOf($ArgumentList, '-EncodedCommand')
		$index | Should -BeGreaterOrEqual 0 -Because "a hidden shell gets its work through -EncodedCommand"
		[System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[$index + 1]))
	}
}

Describe "Start-StartupTaskShell" {
	BeforeEach {
		$script:Started = $null
		$script:Opened = $null
		$script:TaskArguments = @{
			Name       = 'MyTask'
			Command    = 'Open-Workspace MyWorkspace'
			Trigger    = 'SignIn'
			Window     = 'Current'
			ResultFile = 'C:\Logs\.startup-task-MyTask.result'
		}

		Mock Write-LogDebug { }
		Mock Start-Process {
			$script:Started = @{
				FilePath     = $FilePath
				ArgumentList = @($ArgumentList)
				WindowStyle  = "$WindowStyle"
				Verb         = $Verb
				HasVerb      = $PesterBoundParameters.ContainsKey('Verb')
			}
		}
		Mock Open-Terminal {
			$script:Opened = @{
				Command       = ($Command -join "`n")
				Tabs          = @($Command).Count
				WindowId      = $WindowId
				Administrator = [bool]$Administrator
			}
		}
	}

	Context "-Window Hidden" {
		It "starts this PowerShell with no window, no profile and no way to ask a question" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden

			Should -Invoke Start-Process -Times 1 -Exactly
			Should -Invoke Open-Terminal -Times 0 -Exactly
			$script:Started.FilePath | Should -Be (Join-Path $PSHOME 'pwsh.exe')
			$script:Started.WindowStyle | Should -Be 'Hidden'
			$script:Started.ArgumentList | Should -Contain '-NoProfile'
			$script:Started.ArgumentList | Should -Contain '-NonInteractive'
			$script:Started.ArgumentList | Should -Contain '-EncodedCommand'
		}

		It "puts the encoded command last, so nothing after it is read as part of it" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden

			[array]::IndexOf($script:Started.ArgumentList, '-EncodedCommand') | Should -Be ($script:Started.ArgumentList.Count - 2)
		}

		It "hands the shell exactly the task's parameters" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden

			$decoded = Get-TestShellArguments -Text (Get-TestEncodedText -ArgumentList $script:Started.ArgumentList)

			(@($decoded.Keys) | Sort-Object) -join ',' | Should -Be 'Command,Name,ResultFile,Trigger,Window'
			$decoded['Name'] | Should -Be 'MyTask'
			$decoded['Command'] | Should -BeExactly 'Open-Workspace MyWorkspace'
			$decoded['Trigger'] | Should -Be 'SignIn'
			$decoded['Window'] | Should -Be 'Current'
			$decoded['ResultFile'] | Should -BeExactly 'C:\Logs\.startup-task-MyTask.result'
		}

		It "loads the profile without its interactive stages, marks the shell and always exits" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden

			$text = Get-TestEncodedText -ArgumentList $script:Started.ArgumentList
			$statements = @((ConvertTo-TestShellAst -Text $text).EndBlock.Statements)

			$statements[0].Left.Extent.Text | Should -Be '$env:WINUX_STARTUP_SKIP'
			($statements[1] -is [System.Management.Automation.Language.ForEachStatementAst]) | Should -BeTrue
			Test-TestShellMarked -Text $text | Should -BeTrue
			($statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
		}

		It "always exits, whatever -KeepOpen says: <KeepOpen>" -ForEach @(
			@{ KeepOpen = 'OnFailure' }
			@{ KeepOpen = 'Always' }
			@{ KeepOpen = 'Never' }
		) {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden -KeepOpen $KeepOpen

			$statements = @((ConvertTo-TestShellAst -Text (Get-TestEncodedText -ArgumentList $script:Started.ArgumentList)).EndBlock.Statements)

			($statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
		}

		It "starts unelevated without -Administrator" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden

			$script:Started.HasVerb | Should -BeFalse
		}

		It "starts elevated with -Administrator" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden -Administrator

			$script:Started.Verb | Should -Be 'RunAs'
			$script:Started.WindowStyle | Should -Be 'Hidden'
			$script:Started.ArgumentList | Should -Contain '-NonInteractive'
		}

		It "lets a declined consent dialog reach the caller" {
			Mock Start-Process { throw "The operation was canceled by the user." }

			{ Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Hidden -Administrator } | Should -Throw
		}
	}

	Context "-Window Tab" {
		It "opens one terminal tab and starts no process itself" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Window Tab

			Should -Invoke Open-Terminal -Times 1 -Exactly
			Should -Invoke Start-Process -Times 0 -Exactly
			$script:Opened.Tabs | Should -Be 1
		}

		It "is the default window" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			Should -Invoke Open-Terminal -Times 1 -Exactly
			Should -Invoke Start-Process -Times 0 -Exactly
		}

		It "opens the tab in the startup window by default, so the tabs of one startup share it" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			$script:Opened.WindowId | Should -Be 'WinuXStartup'
		}

		It "opens the tab in the window named by -WindowId" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -WindowId 'MyWindow'

			$script:Opened.WindowId | Should -Be 'MyWindow'
		}

		It "opens the tab unelevated without -Administrator" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			$script:Opened.Administrator | Should -BeFalse
		}

		It "opens the tab elevated with -Administrator" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -Administrator

			$script:Opened.Administrator | Should -BeTrue
		}

		It "hands the tab exactly the task's parameters" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			$decoded = Get-TestShellArguments -Text $script:Opened.Command

			(@($decoded.Keys) | Sort-Object) -join ',' | Should -Be 'Command,Name,ResultFile,Trigger,Window'
			$decoded['Command'] | Should -BeExactly 'Open-Workspace MyWorkspace'
			$decoded['ResultFile'] | Should -BeExactly 'C:\Logs\.startup-task-MyTask.result'
		}

		It "adds no profile prelude: a tab loads the profile as any terminal does" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			$ast = ConvertTo-TestShellAst -Text $script:Opened.Command

			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)).Count | Should -Be 0
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'env:WINUX_STARTUP_SKIP' }, $true)).Count | Should -Be 0
		}

		It "lets a failure to open the tab reach the caller" {
			Mock Open-Terminal { throw "Windows Terminal is not installed" }

			{ Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments } | Should -Throw
		}
	}

	Context "-KeepOpen on a tab" {
		It "closes an OnFailure tab after <Status>" -ForEach @(
			@{ Status = 'Succeeded' }
			@{ Status = 'NotDue' }
			@{ Status = 'Disabled' }
			@{ Status = 'OutOfScope' }
			@{ Status = 'AlreadyRunning' }
		) {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen OnFailure

			$last = @((ConvertTo-TestShellAst -Text $script:Opened.Command).EndBlock.Statements)[-1]
			($last -is [System.Management.Automation.Language.IfStatementAst]) | Should -BeTrue
			$condition = [scriptblock]::Create($last.Clauses[0].Item1.Extent.Text)

			$winuxStartupTaskResult = [pscustomobject]@{ Status = $Status }
			[bool](& $condition) | Should -BeTrue
		}

		It "leaves an OnFailure tab open after <Status>, so its output can be read" -ForEach @(
			@{ Status = 'Failed' }
			@{ Status = 'Skipped' }
			@{ Status = 'HandedOff' }
		) {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen OnFailure

			$last = @((ConvertTo-TestShellAst -Text $script:Opened.Command).EndBlock.Statements)[-1]
			$condition = [scriptblock]::Create($last.Clauses[0].Item1.Extent.Text)

			$winuxStartupTaskResult = [pscustomobject]@{ Status = $Status }
			[bool](& $condition) | Should -BeFalse
		}

		It "leaves an OnFailure tab open when the task returned nothing" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen OnFailure

			$last = @((ConvertTo-TestShellAst -Text $script:Opened.Command).EndBlock.Statements)[-1]
			$condition = [scriptblock]::Create($last.Clauses[0].Item1.Extent.Text)

			$winuxStartupTaskResult = $null
			[bool](& $condition) | Should -BeFalse
		}

		It "exits only inside that condition with OnFailure, which is the default" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			$ast = ConvertTo-TestShellAst -Text $script:Opened.Command
			$last = @($ast.EndBlock.Statements)[-1]

			($last -is [System.Management.Automation.Language.IfStatementAst]) | Should -BeTrue
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 1
			@($last.Clauses[0].Item2.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 1
		}

		It "always closes a Never tab" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen Never

			$ast = ConvertTo-TestShellAst -Text $script:Opened.Command

			(@($ast.EndBlock.Statements)[-1] -is [System.Management.Automation.Language.ExitStatementAst]) | Should -BeTrue
			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] }, $true)).Count | Should -Be 0
		}

		It "never closes an Always tab" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen Always

			$ast = ConvertTo-TestShellAst -Text $script:Opened.Command

			@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)).Count | Should -Be 0
			(Get-TestShellArguments -Text $script:Opened.Command)['Name'] | Should -Be 'MyTask'
		}
	}

	Context "the task shell marker" {
		It "marks the tab of a task with a Command, so a new terminal's tasks do not run in it" {
			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments

			Test-TestShellMarked -Text $script:Opened.Command | Should -BeTrue
		}

		It "does not mark the tab of a task <Case>: it is a plain terminal" -ForEach @(
			@{ Case = 'without a Command'; Command = $null }
			@{ Case = 'with an empty Command'; Command = '' }
			@{ Case = 'with a blank Command'; Command = '   ' }
		) {
			$script:TaskArguments.Command = $Command

			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen Always

			Test-TestShellMarked -Text $script:Opened.Command | Should -BeFalse
			(Get-TestShellArguments -Text $script:Opened.Command)['Name'] | Should -Be 'MyTask'
		}

		It "does not mark the tab when the parameters hold no Command key at all" {
			$script:TaskArguments.Remove('Command')

			Start-StartupTaskShell -Name MyTask -Arguments $script:TaskArguments -KeepOpen Always

			Test-TestShellMarked -Text $script:Opened.Command | Should -BeFalse
		}
	}
}
