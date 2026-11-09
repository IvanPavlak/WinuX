#Requires -Modules Pester

BeforeAll {
	$script:SavedConfiguration = $global:Configuration

	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Bootstrap\Functions\Set-StartupTasks.ps1"
	# Dot-sourced so they exist to Mock whatever the session's imported modules hold.
	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	. "$ModuleRoot\Workflow\Functions\New-StartupTaskShellCommand.ps1"

	# Stand-ins for the Task Scheduler and CIM commands, so the mocks below attach to these and
	# the real Task Scheduler is never read or written. They shadow the real commands for this
	# file only, and take any value: the real ones insist on CIM instances no mock can return.
	function Get-ScheduledTask {
		[CmdletBinding()]
		param($TaskPath, $TaskName)
	}
	function Register-ScheduledTask {
		[CmdletBinding()]
		param($TaskPath, $TaskName, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force)
	}
	function Unregister-ScheduledTask {
		[CmdletBinding()]
		param($TaskPath, $TaskName, [switch]$Confirm)
	}
	function New-ScheduledTaskAction {
		[CmdletBinding()]
		param($Execute, $Argument)
	}
	function New-ScheduledTaskTrigger {
		[CmdletBinding()]
		param([switch]$AtLogOn, $User)
	}
	function New-ScheduledTaskPrincipal {
		[CmdletBinding()]
		param($UserId, $LogonType, $RunLevel)
	}
	function New-ScheduledTaskSettingsSet {
		[CmdletBinding()]
		param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [switch]$StartWhenAvailable, $MultipleInstances, $ExecutionTimeLimit)
	}
	function Get-CimClass {
		[CmdletBinding()]
		param($Namespace, $ClassName)
	}
	function New-CimInstance {
		[CmdletBinding()]
		param($CimClass, $Property, [switch]$ClientOnly)
	}

	# One definition as Get-StartupTaskDefinitions returns it, every default filled in.
	function New-TestStartupDefinition {
		param(
			[Parameter(Mandatory)][string]$Name,
			[string[]]$Trigger = @('SignIn'),
			[hashtable]$Options = @{},
			[bool]$Valid = $true,
			[bool]$InScope = $true
		)

		$parameters = @{
			Name          = $Name
			Command       = "Start-$Name"
			Requires      = @()
			Window        = 'Tab'
			KeepOpen      = 'OnFailure'
			Parallel      = $false
			Frequency     = 'EveryTime'
			DayStartHour  = 6
			IntervalHours = 24.0
			Elevation     = 'None'
			Timeout       = 600.0
			Enabled       = $true
		}
		foreach ($key in $Options.Keys) { $parameters[$key] = $Options[$key] }

		$errors = @()
		if (-not $Valid) { $errors = @('Unknown key [Colour]') }

		[pscustomobject]@{
			Name       = $Name
			Trigger    = $Trigger
			InScope    = $InScope
			Valid      = $Valid
			Errors     = $errors
			Legacy     = $false
			Parameters = $parameters
		}
	}
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
}

Describe "Set-StartupTasks" {
	BeforeEach {
		$script:Definitions = @()
		# The scheduled tasks the machine already has under \WinuX\.
		$script:Existing = @()
		$script:Registered = [System.Collections.Generic.List[object]]::new()
		$script:Unregistered = [System.Collections.Generic.List[string]]::new()
		$script:ShellCommands = [System.Collections.Generic.List[object]]::new()
		$script:CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

		$global:Configuration = @{
			Startup = @{ Conditions = @{ Network = @{ Test = '$true'; Timeout = 30 }; MyVpn = @{ Test = '$false' } } }
		}

		Mock Get-StartupTaskDefinitions { $script:Definitions }
		Mock New-StartupTaskShellCommand {
			$script:ShellCommands.Add(@{
					Command     = $Command
					Arguments   = $Arguments
					LoadProfile = [bool]$LoadProfile
					TaskShell   = [bool]$TaskShell
					ExitAlways  = [bool]$ExitAlways
					Encoded     = [bool]$Encoded
				})
			if ($Arguments) { "encoded-task-$($Arguments.Name)-$($Arguments.Trigger)" } else { "encoded-runner-$($Command -replace '\W', '_')" }
		}
		Mock Get-ScheduledTask { $script:Existing }
		Mock Register-ScheduledTask {
			$script:Registered.Add(@{
					TaskPath    = $TaskPath
					TaskName    = $TaskName
					Action      = $Action
					Trigger     = $Trigger
					Principal   = $Principal
					Settings    = $Settings
					Description = $Description
					Force       = [bool]$Force
				})
		}
		Mock Unregister-ScheduledTask { $script:Unregistered.Add("$TaskPath$TaskName") }
		Mock New-ScheduledTaskAction { [pscustomobject]@{ Execute = $Execute; Argument = $Argument } }
		Mock New-ScheduledTaskTrigger { [pscustomobject]@{ Kind = 'LogOn'; AtLogOn = [bool]$AtLogOn; User = $User } }
		Mock New-ScheduledTaskPrincipal { [pscustomobject]@{ UserId = $UserId; LogonType = "$LogonType"; RunLevel = "$RunLevel" } }
		Mock New-ScheduledTaskSettingsSet {
			[pscustomobject]@{
				AllowStartIfOnBatteries    = [bool]$AllowStartIfOnBatteries
				DontStopIfGoingOnBatteries = [bool]$DontStopIfGoingOnBatteries
				StartWhenAvailable         = [bool]$StartWhenAvailable
				MultipleInstances          = "$MultipleInstances"
				ExecutionTimeLimit         = $ExecutionTimeLimit
			}
		}
		Mock Get-CimClass { [pscustomobject]@{ Namespace = $Namespace; ClassName = $ClassName } }
		Mock New-CimInstance { [pscustomobject]@{ Kind = $CimClass.ClassName; Property = $Property; ClientOnly = [bool]$ClientOnly } }
		Mock Test-AdminPrivileges { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
	}

	Context "the runner of each trigger" {
		It "registers one runner per trigger in use, and none for a trigger nothing uses or for TerminalOpen" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger SignIn
				New-TestStartupDefinition -Name B -Trigger SignIn, Wake
				New-TestStartupDefinition -Name C -Trigger TerminalOpen
			)

			Set-StartupTasks

			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-SignIn,StartupTasks-Wake'
			$script:Unregistered.Count | Should -Be 0
		}

		It "registers a runner for each of <Trigger>" -ForEach @(
			@{ Trigger = 'SignIn' }
			@{ Trigger = 'Unlock' }
			@{ Trigger = 'Wake' }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger $Trigger)

			Set-StartupTasks

			$script:Registered.Count | Should -Be 1
			$script:Registered[0].TaskName | Should -Be "StartupTasks-$Trigger"
			$script:Registered[0].TaskPath | Should -Be '\WinuX\'
			# Replacing a task of the same name is what makes a second run harmless.
			$script:Registered[0].Force | Should -BeTrue
		}

		It "registers nothing for a machine whose tasks all run in a newly opened terminal" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger TerminalOpen)

			Set-StartupTasks

			$script:Registered.Count | Should -Be 0
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
		}

		It "has the runner call Invoke-StartupTasks for its trigger, from a shell that loads the profile and always exits" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger Wake)

			Set-StartupTasks

			$script:ShellCommands.Count | Should -Be 1
			$script:ShellCommands[0].Command | Should -Be 'Invoke-StartupTasks -Trigger Wake'
			$script:ShellCommands[0].LoadProfile | Should -BeTrue
			$script:ShellCommands[0].ExitAlways | Should -BeTrue
			$script:ShellCommands[0].Encoded | Should -BeTrue
		}

		It "starts that shell with no window, no profile of its own and no way to ask a question" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks

			$action = $script:Registered[0].Action
			$action.Execute | Should -BeLike '*\conhost.exe'
			$action.Argument | Should -BeLike '--headless *'
			$action.Argument.Contains((Join-Path $PSHOME 'pwsh.exe')) | Should -BeTrue
			$action.Argument | Should -BeLike '* -NoProfile *'
			$action.Argument | Should -BeLike '* -NonInteractive *'
			$action.Argument | Should -BeLike '* -EncodedCommand encoded-runner-Invoke_StartupTasks__Trigger_SignIn'
		}

		It "runs the runner as the signed-in user, unelevated" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks

			$principal = $script:Registered[0].Principal
			$principal.UserId | Should -Be $script:CurrentUser
			$principal.LogonType | Should -Be 'Interactive'
			$principal.RunLevel | Should -Be 'Limited'
		}

		It "lets the task start on battery and keep running there, with no time limit" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks

			$settings = $script:Registered[0].Settings
			$settings.AllowStartIfOnBatteries | Should -BeTrue
			$settings.DontStopIfGoingOnBatteries | Should -BeTrue
			$settings.MultipleInstances | Should -Be 'IgnoreNew'
			$settings.ExecutionTimeLimit | Should -Be ([timespan]::Zero)
		}

		It "fires the SignIn runner at this user's sign-in" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks

			$trigger = $script:Registered[0].Trigger
			$trigger.Kind | Should -Be 'LogOn'
			$trigger.AtLogOn | Should -BeTrue
			$trigger.User | Should -Be $script:CurrentUser
			Should -Invoke New-CimInstance -Times 0 -Exactly
		}

		It "fires the Unlock runner when this user unlocks the workstation" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger Unlock)

			Set-StartupTasks

			$trigger = $script:Registered[0].Trigger
			$trigger.Kind | Should -Be 'MSFT_TaskSessionStateChangeTrigger'
			# 8 is TASK_SESSION_UNLOCK.
			$trigger.Property.StateChange | Should -Be 8
			$trigger.Property.UserId | Should -Be $script:CurrentUser
			$trigger.Property.Enabled | Should -BeTrue
			$trigger.ClientOnly | Should -BeTrue
			Should -Invoke New-ScheduledTaskTrigger -Times 0 -Exactly
		}

		It "fires the Wake runner on the System log's resume-from-sleep event" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger Wake)

			Set-StartupTasks

			$trigger = $script:Registered[0].Trigger
			$trigger.Kind | Should -Be 'MSFT_TaskEventTrigger'
			$trigger.Property.Enabled | Should -BeTrue
			$trigger.ClientOnly | Should -BeTrue

			$subscription = [xml]$trigger.Property.Subscription
			$subscription.SelectSingleNode('/QueryList/Query').GetAttribute('Path') | Should -Be 'System'
			$subscription.SelectSingleNode('/QueryList/Query/Select').InnerText | Should -Match 'Microsoft-Windows-Power-Troubleshooter'
			$subscription.SelectSingleNode('/QueryList/Query/Select').InnerText | Should -Match 'EventID=1\b'
		}

		It "asks for Administrator privileges once, before it registers anything" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn, Unlock, Wake)
			Mock Test-AdminPrivileges { $script:RegisteredWhenAsked = $script:Registered.Count }

			Set-StartupTasks

			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly -ParameterFilter { $CheckOnly }
			$script:RegisteredWhenAsked | Should -Be 0
			$script:Registered.Count | Should -Be 3
		}

		It "returns nothing" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks | Should -BeNullOrEmpty
		}
	}

	Context "tasks that do not count" {
		It "registers nothing for a task that is <Case>" -ForEach @(
			@{ Case = 'out of scope'; Valid = $true; InScope = $false; Enabled = $true }
			@{ Case = 'not enabled'; Valid = $true; InScope = $true; Enabled = $false }
			@{ Case = 'not valid'; Valid = $false; InScope = $true; Enabled = $true }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn, Unlock, Wake -Valid $Valid -InScope $InScope -Options @{ Enabled = $Enabled })

			Set-StartupTasks

			$script:Registered.Count | Should -Be 0
			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
		}

		It "registers nothing for a Silent task that is <Case>" -ForEach @(
			@{ Case = 'out of scope'; Valid = $true; InScope = $false; Enabled = $true }
			@{ Case = 'not enabled'; Valid = $true; InScope = $true; Enabled = $false }
			@{ Case = 'not valid'; Valid = $false; InScope = $true; Enabled = $true }
		) {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Valid $Valid -InScope $InScope -Options @{ Enabled = $Enabled; Elevation = 'Silent' })

			Set-StartupTasks

			$script:Registered.Count | Should -Be 0
			$script:ShellCommands.Count | Should -Be 0
		}

		It "adds no trigger for them next to a task that counts" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger SignIn
				New-TestStartupDefinition -Name Elsewhere -Trigger Unlock -InScope $false
				New-TestStartupDefinition -Name Parked -Trigger Wake -Options @{ Enabled = $false }
				New-TestStartupDefinition -Name Broken -Trigger Wake -Valid $false
			)

			Set-StartupTasks

			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-SignIn'
		}
	}

	Context "a task with Elevation Silent" {
		It "gets a scheduled task of its own per trigger, with the highest privileges" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn, Unlock -Options @{ Elevation = 'Silent' })

			Set-StartupTasks

			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTask-Silent-S-SignIn,StartupTask-Silent-S-Unlock'
			foreach ($task in $script:Registered) {
				$task.TaskPath | Should -Be '\WinuX\'
				$task.Principal.RunLevel | Should -Be 'Highest'
				$task.Principal.UserId | Should -Be $script:CurrentUser
			}
		}

		It "is no reason for the trigger's runner to exist" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent' })

			Set-StartupTasks

			@($script:Registered | Where-Object { $_.TaskName -like 'StartupTasks-*' }).Count | Should -Be 0
		}

		It "is registered next to the runner an ordinary task on the same trigger needs" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent' }
				New-TestStartupDefinition -Name A -Trigger SignIn
			)

			Set-StartupTasks

			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-SignIn,StartupTask-Silent-S-SignIn'
			(($script:Registered | ForEach-Object { $_.Principal.RunLevel }) -join ',') | Should -Be 'Limited,Highest'
		}

		It "fires on the same event as the runner of its trigger" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger Unlock -Options @{ Elevation = 'Silent' })

			Set-StartupTasks

			$script:Registered[0].Trigger.Kind | Should -Be 'MSFT_TaskSessionStateChangeTrigger'
			$script:Registered[0].Trigger.Property.StateChange | Should -Be 8
		}

		It "runs Invoke-StartupTask itself, with the task's options copied in" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name S -Trigger Wake -Options @{
					Elevation = 'Silent'
					Command   = 'Clear-MyCache -All'
					Window    = 'Hidden'
					Frequency = 'OncePerDay'
					Timeout   = 90.0
				}
			)

			Set-StartupTasks

			$script:ShellCommands.Count | Should -Be 1
			$shell = $script:ShellCommands[0]
			$shell.Command | Should -BeNullOrEmpty
			$shell.LoadProfile | Should -BeTrue
			$shell.ExitAlways | Should -BeTrue
			$shell.Encoded | Should -BeTrue

			$frozen = $shell.Arguments
			$frozen.Name | Should -Be 'S'
			$frozen.Command | Should -Be 'Clear-MyCache -All'
			$frozen.Window | Should -Be 'Hidden'
			$frozen.Frequency | Should -Be 'OncePerDay'
			$frozen.Timeout | Should -Be 90
			$frozen.Elevation | Should -Be 'Silent'
			$frozen.Enabled | Should -BeTrue
			$script:Registered[0].Action.Argument | Should -BeLike '* -EncodedCommand encoded-task-S-Wake'
		}

		It "freezes the trigger it was registered for" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn, Wake -Options @{ Elevation = 'Silent' })

			Set-StartupTasks

			(($script:ShellCommands | ForEach-Object { $_.Arguments.Trigger }) -join ',') | Should -Be 'SignIn,Wake'
		}

		It "never freezes a parallel run: nothing would collect it" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent'; Parallel = $true })

			Set-StartupTasks

			$script:ShellCommands[0].Arguments.Parallel | Should -BeFalse
		}

		It "freezes only the conditions the task requires" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent'; Requires = @('Network') })

			Set-StartupTasks

			$frozen = $script:ShellCommands[0].Arguments
			($frozen.Requires -join ',') | Should -Be 'Network'
			(@($frozen.ConditionDefinitions.Keys) -join ',') | Should -Be 'Network'
			$frozen.ConditionDefinitions['Network'].Test | Should -Be '$true'
			$frozen.ConditionDefinitions['Network'].Timeout | Should -Be 30
		}

		It "freezes no condition for a task that requires none" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent' })

			Set-StartupTasks

			$frozen = $script:ShellCommands[0].Arguments
			$frozen.ContainsKey('ConditionDefinitions') | Should -BeTrue
			$frozen.ConditionDefinitions.Count | Should -Be 0
		}

		It "leaves the definition it copied from untouched" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent'; Parallel = $true; Requires = @('Network') })

			Set-StartupTasks

			$parameters = $script:Definitions[0].Parameters
			$parameters.Parallel | Should -BeTrue
			$parameters.ContainsKey('Trigger') | Should -BeFalse
			$parameters.ContainsKey('ConditionDefinitions') | Should -BeFalse
		}
	}

	Context "scheduled tasks nothing needs any more" {
		It "removes stale tasks of both name patterns and leaves every other task in the folder alone" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)
			$script:Existing = @(
				[pscustomobject]@{ TaskName = 'StartupTasks-SignIn' }
				[pscustomobject]@{ TaskName = 'StartupTasks-Wake' }
				[pscustomobject]@{ TaskName = 'StartupTask-Silent-Old-SignIn' }
				[pscustomobject]@{ TaskName = 'SomethingElse' }
				[pscustomobject]@{ TaskName = 'StartupTaskOfMine' }
			)

			Set-StartupTasks

			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTasks-Wake,\WinuX\StartupTask-Silent-Old-SignIn'
			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-SignIn'
		}

		It "looks only in the \WinuX\ folder" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn)

			Set-StartupTasks

			Should -Invoke Get-ScheduledTask -Times 1 -Exactly
			Should -Invoke Get-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskPath -eq '\WinuX\' }
		}

		It "removes without asking for a confirmation nobody is there to give" {
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTasks-Wake' })

			Set-StartupTasks

			Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters.ContainsKey('Confirm') -and -not $Confirm }
		}

		It "removes the last scheduled task of a machine whose startup tasks were all deleted" {
			$script:Definitions = @()
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTasks-SignIn' })

			Set-StartupTasks

			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTasks-SignIn'
			$script:Registered.Count | Should -Be 0
			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		}

		It "removes the Silent task of a task that is not Silent any more, and registers its runner" {
			$script:Definitions = @(New-TestStartupDefinition -Name S -Trigger SignIn)
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTask-Silent-S-SignIn' })

			Set-StartupTasks

			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTask-Silent-S-SignIn'
			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-SignIn'
		}
	}

	Context "nothing to do" {
		It "neither asks for Administrator privileges nor registers when nothing is needed and nothing is stale" {
			$script:Definitions = @(New-TestStartupDefinition -Name C -Trigger TerminalOpen)
			$script:Existing = @([pscustomobject]@{ TaskName = 'SomethingElse' })

			{ Set-StartupTasks } | Should -Not -Throw

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Register-ScheduledTask -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}

		It "does the same when no startup task is configured at all" {
			Set-StartupTasks

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Register-ScheduledTask -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}
	}

	Context "-List" {
		BeforeEach {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger SignIn, Wake
				New-TestStartupDefinition -Name S -Trigger Wake -Options @{ Elevation = 'Silent' }
			)
			$script:Existing = @(
				[pscustomobject]@{ TaskName = 'StartupTasks-SignIn' }
				[pscustomobject]@{ TaskName = 'StartupTasks-Unlock' }
				[pscustomobject]@{ TaskName = 'SomethingElse' }
			)
		}

		It "reports what is registered, what is missing and what is stale" {
			$listed = @(Set-StartupTasks -List)

			(($listed | ForEach-Object { "$($_.TaskName)=$($_.State)" }) -join ',') | Should -Be 'StartupTasks-SignIn=Registered,StartupTasks-Wake=Missing,StartupTask-Silent-S-Wake=Missing,StartupTasks-Unlock=Stale'
		}

		It "says which trigger and run level each needed task has, and neither for a stale one" {
			$listed = @(Set-StartupTasks -List)

			$runner = $listed | Where-Object { $_.TaskName -eq 'StartupTasks-Wake' }
			$runner.Trigger | Should -Be 'Wake'
			$runner.RunLevel | Should -Be 'Limited'

			$silent = $listed | Where-Object { $_.TaskName -eq 'StartupTask-Silent-S-Wake' }
			$silent.Trigger | Should -Be 'Wake'
			$silent.RunLevel | Should -Be 'Highest'

			$stale = $listed | Where-Object { $_.State -eq 'Stale' }
			$stale.Trigger | Should -BeNullOrEmpty
			$stale.RunLevel | Should -BeNullOrEmpty
		}

		It "changes nothing and needs no Administrator privileges" {
			Set-StartupTasks -List | Out-Null

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Register-ScheduledTask -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}

		It "returns nothing when nothing is needed and nothing is there" {
			$script:Definitions = @()
			$script:Existing = @()

			Set-StartupTasks -List | Should -BeNullOrEmpty
		}

		It "lists every startup scheduled task as stale together with -Remove" {
			$listed = @(Set-StartupTasks -List -Remove)

			(($listed | ForEach-Object { "$($_.TaskName)=$($_.State)" }) -join ',') | Should -Be 'StartupTasks-SignIn=Stale,StartupTasks-Unlock=Stale'
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}
	}

	Context "-Remove" {
		BeforeEach {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger SignIn
				New-TestStartupDefinition -Name S -Trigger Wake -Options @{ Elevation = 'Silent' }
			)
			$script:Existing = @(
				[pscustomobject]@{ TaskName = 'StartupTasks-SignIn' }
				[pscustomobject]@{ TaskName = 'StartupTask-Silent-S-Wake' }
				[pscustomobject]@{ TaskName = 'SomethingElse' }
			)
		}

		It "removes every startup scheduled task, whatever the configuration says, and registers none" {
			Set-StartupTasks -Remove

			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTasks-SignIn,\WinuX\StartupTask-Silent-S-Wake'
			$script:Registered.Count | Should -Be 0
			Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		}

		It "does not even read the configured tasks" {
			Set-StartupTasks -Remove

			Should -Invoke Get-StartupTaskDefinitions -Times 0 -Exactly
			Should -Invoke New-StartupTaskShellCommand -Times 0 -Exactly
		}

		It "asks for nothing when there is nothing to remove" {
			$script:Existing = @([pscustomobject]@{ TaskName = 'SomethingElse' })

			Set-StartupTasks -Remove

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}
	}

	Context "-WhatIf" {
		It "registers nothing, removes nothing and does not ask for Administrator privileges" {
			$script:Definitions = @(
				New-TestStartupDefinition -Name A -Trigger SignIn, Unlock, Wake
				New-TestStartupDefinition -Name S -Trigger SignIn -Options @{ Elevation = 'Silent' }
			)
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTask-Silent-Old-Wake' })

			Set-StartupTasks -WhatIf

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Register-ScheduledTask -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
			Should -Invoke New-ScheduledTaskAction -Times 0 -Exactly
			Should -Invoke New-CimInstance -Times 0 -Exactly
		}

		It "removes nothing with -Remove either" {
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTasks-SignIn' })

			Set-StartupTasks -Remove -WhatIf

			Should -Invoke Test-AdminPrivileges -Times 0 -Exactly
			Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
		}
	}

	Context "when Windows refuses" {
		It "goes on with the next scheduled task after one that could not be registered" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn, Unlock, Wake)
			$script:Existing = @([pscustomobject]@{ TaskName = 'StartupTask-Silent-Old-Wake' })
			Mock Register-ScheduledTask {
				if ($TaskName -eq 'StartupTasks-SignIn') { throw "Access is denied." }
				$script:Registered.Add(@{ TaskName = $TaskName })
			}

			{ Set-StartupTasks } | Should -Not -Throw

			Should -Invoke Register-ScheduledTask -Times 3 -Exactly
			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-Unlock,StartupTasks-Wake'
			# The removals still happen too.
			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTask-Silent-Old-Wake'
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "goes on with the next scheduled task after one whose trigger could not be built" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger Unlock, Wake)
			Mock Get-CimClass { throw "Invalid namespace" } -ParameterFilter { $ClassName -eq 'MSFT_TaskSessionStateChangeTrigger' }

			{ Set-StartupTasks } | Should -Not -Throw

			(($script:Registered | ForEach-Object { $_.TaskName }) -join ',') | Should -Be 'StartupTasks-Wake'
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "goes on with the next removal after one that failed" {
			$script:Existing = @(
				[pscustomobject]@{ TaskName = 'StartupTasks-SignIn' }
				[pscustomobject]@{ TaskName = 'StartupTasks-Wake' }
			)
			Mock Unregister-ScheduledTask {
				if ($TaskName -eq 'StartupTasks-SignIn') { throw "Access is denied." }
				$script:Unregistered.Add("$TaskPath$TaskName")
			}

			{ Set-StartupTasks -Remove } | Should -Not -Throw

			Should -Invoke Unregister-ScheduledTask -Times 2 -Exactly
			($script:Unregistered -join ',') | Should -Be '\WinuX\StartupTasks-Wake'
			Should -Invoke Write-LogError -Times 1 -Exactly
		}

		It "says once, at the end, that something could not be changed, and stays quiet when all went well" {
			$script:Definitions = @(New-TestStartupDefinition -Name A -Trigger SignIn, Wake)

			Set-StartupTasks
			Should -Invoke Write-LogWarning -Times 0 -Exactly

			Mock Register-ScheduledTask { throw "Access is denied." }
			Set-StartupTasks
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}
	}
}
