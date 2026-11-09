#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Workflow\Functions\Get-StartupTaskDefinitions.ps1"
	# Dot-sourced so they exist to Mock whatever the session's imported modules hold.
	. "$ModuleRoot\Bootstrap\Functions\Test-MachineTypeScope.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Resolve-RepositoryUpdateScope.ps1"
}

Describe "Get-StartupTaskDefinitions" {
	BeforeEach {
		# Every test hands its own configuration over with -Configuration; the global one is
		# never read. The machine scope and the repository scope belong to their own tests.
		$script:MachineInScope = $true
		$script:RepositoryScope = @{ All = $true; Groups = @() }

		Mock Test-MachineTypeScope { $script:MachineInScope }
		Mock Resolve-RepositoryUpdateScope { $script:RepositoryScope }
	}

	Context "what is read" {
		It "returns nothing when the configuration <Case>" -ForEach @(
			@{ Case = 'is empty'; Source = @{} }
			@{ Case = 'has an empty Startup section'; Source = @{ Startup = @{} } }
			@{ Case = 'has an empty task list'; Source = @{ Startup = @{ Tasks = @() } } }
			@{ Case = 'is missing altogether'; Source = $null }
		) {
			@(Get-StartupTaskDefinitions -Configuration $Source).Count | Should -Be 0
		}

		It "fills in every default" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace'; Trigger = 'SignIn' }) }
			}

			$definition.Name | Should -Be 'MyTask'
			($definition.Trigger -join ',') | Should -Be 'SignIn'
			$definition.InScope | Should -BeTrue
			$definition.Valid | Should -BeTrue
			$definition.Errors.Count | Should -Be 0
			$definition.Legacy | Should -BeFalse

			$parameters = $definition.Parameters
			$parameters.Name | Should -Be 'MyTask'
			$parameters.Command | Should -Be 'Open-Workspace MyWorkspace'
			@($parameters.Requires).Count | Should -Be 0
			$parameters.Window | Should -Be 'Tab'
			$parameters.KeepOpen | Should -Be 'OnFailure'
			$parameters.Parallel | Should -BeFalse
			$parameters.Frequency | Should -Be 'EveryTime'
			$parameters.DayStartHour | Should -Be 6
			$parameters.IntervalHours | Should -Be 24
			$parameters.Elevation | Should -Be 'None'
			$parameters.Timeout | Should -Be 600
			$parameters.Enabled | Should -BeTrue
		}

		It "leaves the scope and the trigger out of the parameters of a task that names neither scope" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Command = 'Open-Workspace MyWorkspace'; Trigger = 'SignIn' }) }
			}

			# Parameters is splatted onto Invoke-StartupTask as it is.
			$definition.Parameters.ContainsKey('Machine') | Should -BeFalse
			$definition.Parameters.ContainsKey('Hostname') | Should -BeFalse
			$definition.Parameters.ContainsKey('Trigger') | Should -BeFalse
		}

		It "reads every option of an entry" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{
					Conditions = @{ Network = @{ Test = '$true' }; MyVpn = @{ Test = '$true' } }
					Tasks      = @(
						@{
							Name          = 'My-Task_2'
							Command       = 'Update-Something -Quiet'
							Trigger       = @('Unlock', 'Wake')
							Machine       = 'PC/Laptop'
							Hostname      = @($env:COMPUTERNAME, 'Other-PC')
							Requires      = @('Network', 'MyVpn')
							Window        = 'Hidden'
							KeepOpen      = 'Never'
							Parallel      = $true
							Frequency     = 'Interval'
							DayStartHour  = 4
							IntervalHours = 0.5
							Elevation     = 'Prompt'
							Timeout       = 30
							Enabled       = $false
						}
					)
				}
			}

			$definition.Valid | Should -BeTrue
			$definition.Name | Should -Be 'My-Task_2'
			($definition.Trigger -join ',') | Should -Be 'Unlock,Wake'

			$parameters = $definition.Parameters
			$parameters.Command | Should -Be 'Update-Something -Quiet'
			$parameters.Machine | Should -Be 'PC/Laptop'
			($parameters.Hostname -join ',') | Should -Be "$env:COMPUTERNAME,Other-PC"
			($parameters.Requires -join ',') | Should -Be 'Network,MyVpn'
			$parameters.Window | Should -Be 'Hidden'
			$parameters.KeepOpen | Should -Be 'Never'
			$parameters.Parallel | Should -BeTrue
			$parameters.Frequency | Should -Be 'Interval'
			$parameters.DayStartHour | Should -Be 4
			$parameters.IntervalHours | Should -Be 0.5
			$parameters.Elevation | Should -Be 'Prompt'
			$parameters.Timeout | Should -Be 30
			$parameters.Enabled | Should -BeFalse
		}

		It "returns the canonical spelling whatever the casing in the file" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Command = 'Do-Something'; Trigger = 'signin'; Window = 'hidden'; KeepOpen = 'never'; Frequency = 'onceperday'; Elevation = 'silent' }) }
			}

			$definition.Valid | Should -BeTrue
			($definition.Trigger -join ',') | Should -BeExactly 'SignIn'
			$definition.Parameters.Window | Should -BeExactly 'Hidden'
			$definition.Parameters.KeepOpen | Should -BeExactly 'Never'
			$definition.Parameters.Frequency | Should -BeExactly 'OncePerDay'
			$definition.Parameters.Elevation | Should -BeExactly 'Silent'
		}

		It "returns the tasks in configuration order" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{
						Tasks = @(
							@{ Name = 'Third'; Trigger = 'SignIn' }
							@{ Name = 'First'; Trigger = 'Wake' }
							@{ Name = 'Second'; Trigger = 'SignIn' }
						)
					}
				})

			($definitions.Name -join ',') | Should -Be 'Third,First,Second'
		}

		It "takes a single task written without the list around it" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @{ Name = 'MyTask'; Trigger = 'SignIn' } } }

			@($definition).Count | Should -Be 1
			$definition.Name | Should -Be 'MyTask'
			$definition.Valid | Should -BeTrue
		}

		It "skips an empty slot in the list" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @($null, @{ Name = 'MyTask'; Trigger = 'SignIn' }) } })

			$definitions.Count | Should -Be 1
			$definitions[0].Name | Should -Be 'MyTask'
		}

		It "trims the name" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = '  MyTask '; Trigger = 'SignIn' }) } }

			$definition.Valid | Should -BeTrue
			$definition.Name | Should -BeExactly 'MyTask'
			$definition.Parameters.Name | Should -BeExactly 'MyTask'
		}
	}

	Context "Trigger" {
		It "takes several triggers" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = @('Wake', 'SignIn', 'TerminalOpen') }) } }

			$definition.Valid | Should -BeTrue
			($definition.Trigger -join ',') | Should -Be 'Wake,SignIn,TerminalOpen'
		}

		It "returns each trigger once, in its canonical spelling" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = @('signin', 'SIGNIN', ' Wake ', 'SignIn') }) } }

			$definition.Valid | Should -BeTrue
			($definition.Trigger -join ',') | Should -BeExactly 'SignIn,Wake'
		}

		It "keeps the triggers it knows next to one it rejects" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = @('Boot', 'SignIn') }) } }

			$definition.Valid | Should -BeFalse
			$definition.Errors.Count | Should -Be 1
			($definition.Trigger -join ',') | Should -Be 'SignIn'
		}
	}

	Context "an entry that breaks a rule" {
		It "is returned as not valid, with one error, when it <Case>" -ForEach @(
			@{ Case = 'has no Name'; Task = @{ Command = 'Do-Something'; Trigger = 'SignIn' } }
			@{ Case = 'has a blank Name'; Task = @{ Name = '   '; Trigger = 'SignIn' } }
			@{ Case = 'has a Name with a space'; Task = @{ Name = 'My Task'; Trigger = 'SignIn' } }
			@{ Case = 'has a Name with a dot'; Task = @{ Name = 'My.Task'; Trigger = 'SignIn' } }
			@{ Case = 'has a Name that starts with a hyphen'; Task = @{ Name = '-MyTask'; Trigger = 'SignIn' } }
			@{ Case = 'has a key that is no option'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Colour = 'Blue' } }
			@{ Case = 'has no Trigger'; Task = @{ Name = 'MyTask'; Command = 'Do-Something' } }
			@{ Case = 'has a blank Trigger'; Task = @{ Name = 'MyTask'; Trigger = '  ' } }
			@{ Case = 'has an empty Trigger list'; Task = @{ Name = 'MyTask'; Trigger = @() } }
			@{ Case = 'asks for the Boot trigger'; Task = @{ Name = 'MyTask'; Trigger = 'Boot' } }
			@{ Case = 'asks for a trigger that does not exist'; Task = @{ Name = 'MyTask'; Trigger = 'Shutdown' } }
			@{ Case = 'asks for a window that does not exist'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Window = 'Popup' } }
			@{ Case = 'asks for the Current window, which only a manual run has'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Window = 'Current' } }
			@{ Case = 'has an unknown KeepOpen'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; KeepOpen = 'Sometimes' } }
			@{ Case = 'has an unknown Frequency'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Frequency = 'Weekly' } }
			@{ Case = 'has an unknown Elevation'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Elevation = 'Admin' } }
			@{ Case = 'has a DayStartHour of 24'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = 24 } }
			@{ Case = 'has a negative DayStartHour'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = -1 } }
			@{ Case = 'has a DayStartHour that is no whole hour'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = 6.5 } }
			@{ Case = 'has a DayStartHour that is no number'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = 'noon' } }
			@{ Case = 'has IntervalHours that are no number'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; IntervalHours = 'often' } }
			@{ Case = 'has a Timeout that is no number'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Timeout = 'long' } }
			@{ Case = 'has a negative Timeout'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Timeout = -1 } }
			@{ Case = 'requires a condition that is not defined'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Requires = 'MyVpn' } }
			@{ Case = 'combines Prompt with TerminalOpen'; Task = @{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Elevation = 'Prompt' } }
			@{ Case = 'combines Silent with TerminalOpen'; Task = @{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Elevation = 'Silent' } }
			@{ Case = 'combines Silent with TerminalOpen among other triggers'; Task = @{ Name = 'MyTask'; Trigger = @('SignIn', 'TerminalOpen'); Elevation = 'Silent' } }
		) {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{ Conditions = @{ Network = @{ Test = '$true' } }; Tasks = @($Task) }
				})

			# Still returned: Invoke-StartupTasks reports it at every run.
			$definitions.Count | Should -Be 1
			$definitions[0].Valid | Should -BeFalse
			$definitions[0].Errors.Count | Should -Be 1
		}

		It "is valid when it <Case>" -ForEach @(
			@{ Case = 'has IntervalHours of 0'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; IntervalHours = 0 } }
			@{ Case = 'has negative IntervalHours'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; IntervalHours = -1 } }
			@{ Case = 'has a Timeout of 0'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Timeout = 0 } }
			@{ Case = 'starts the day at midnight'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = 0 } }
			@{ Case = 'starts the day at 23:00'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = 23 } }
			@{ Case = 'writes its numbers as text'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = '7'; IntervalHours = '1.5'; Timeout = '90' } }
			@{ Case = 'has a blank Elevation'; Task = @{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Elevation = ' ' } }
			@{ Case = 'spells out the None elevation'; Task = @{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Elevation = 'None' } }
			@{ Case = 'combines Relaunch with TerminalOpen'; Task = @{ Name = 'MyTask'; Trigger = 'TerminalOpen'; Elevation = 'Relaunch' } }
			@{ Case = 'combines Prompt with SignIn'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Elevation = 'Prompt' } }
			@{ Case = 'requires a condition that is defined'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Requires = 'Network' } }
			@{ Case = 'requires a condition in another casing'; Task = @{ Name = 'MyTask'; Trigger = 'SignIn'; Requires = 'network' } }
			@{ Case = 'has a Name of digits, hyphens and underscores'; Task = @{ Name = '2nd_Task-b'; Trigger = 'SignIn' } }
		) {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Conditions = @{ Network = @{ Test = '$true' } }; Tasks = @($Task) }
			}

			$definition.Valid | Should -BeTrue
			$definition.Errors.Count | Should -Be 0
		}

		It "reads numbers written as text" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; DayStartHour = '7'; IntervalHours = '1.5'; Timeout = '90' }) }
			}

			$definition.Parameters.DayStartHour | Should -Be 7
			$definition.Parameters.IntervalHours | Should -Be 1.5
			$definition.Parameters.Timeout | Should -Be 90
		}

		It "treats a blank Elevation as none" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Elevation = '' }) } }

			$definition.Parameters.Elevation | Should -Be 'None'
		}

		It "lists every rule an entry breaks" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'My Task'; Trigger = 'Shutdown'; Window = 'Popup'; Timeout = 'long'; Colour = 'Blue' }) }
			}

			$definition.Valid | Should -BeFalse
			$definition.Errors.Count | Should -Be 5
		}

		It "names every Requires entry that has no condition" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Conditions = @{ Network = @{ Test = '$true' } }; Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Requires = @('Network', 'MyVpn', 'Proxy') }) }
			}

			$definition.Valid | Should -BeFalse
			$definition.Errors.Count | Should -Be 2
			($definition.Parameters.Requires -join ',') | Should -Be 'Network,MyVpn,Proxy'
		}

		It "rejects a Requires name when no conditions are configured at all" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Requires = 'Network' }) } }

			$definition.Valid | Should -BeFalse
		}

		It "gives a task without a usable Name its position as the name" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }, @{ Command = 'Do-Something'; Trigger = 'SignIn' }) }
				})

			$definitions[1].Name | Should -Be '#2'
			$definitions[1].Valid | Should -BeFalse
		}

		It "rejects a Name an earlier task uses, in any casing, and keeps the earlier task valid" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }, @{ Name = 'mytask'; Trigger = 'Wake' }) }
				})

			$definitions.Count | Should -Be 2
			$definitions[0].Valid | Should -BeTrue
			$definitions[1].Valid | Should -BeFalse
			$definitions[1].Errors.Count | Should -Be 1
		}

		It "returns an entry that is not a hashtable as not valid, and still reads the next one" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{ Tasks = @('Open-Workspace MyWorkspace', @{ Name = 'MyTask'; Trigger = 'SignIn' }) }
				})

			$definitions.Count | Should -Be 2
			$definitions[0].Name | Should -Be '#1'
			$definitions[0].Valid | Should -BeFalse
			$definitions[0].InScope | Should -BeFalse
			$definitions[0].Errors.Count | Should -Be 1
			@($definitions[0].Trigger).Count | Should -Be 0
			$definitions[0].Parameters.Count | Should -Be 0

			$definitions[1].Name | Should -Be 'MyTask'
			$definitions[1].Valid | Should -BeTrue
		}
	}

	Context "KeepOpen" {
		It "defaults to OnFailure for a task with a Command" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Command = 'Do-Something'; Trigger = 'SignIn' }) } }

			$definition.Parameters.KeepOpen | Should -Be 'OnFailure'
		}

		It "defaults to Always for a task <Case>, which is a plain terminal" -ForEach @(
			@{ Case = 'without a Command'; Task = @{ Name = 'MyTerminal'; Trigger = 'SignIn' } }
			@{ Case = 'with a blank Command'; Task = @{ Name = 'MyTerminal'; Command = '   '; Trigger = 'SignIn' } }
		) {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @($Task) } }

			$definition.Valid | Should -BeTrue
			$definition.Parameters.KeepOpen | Should -Be 'Always'
		}

		It "keeps the KeepOpen a task without a Command asks for" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTerminal'; Trigger = 'SignIn'; KeepOpen = 'Never' }) } }

			$definition.Parameters.KeepOpen | Should -Be 'Never'
		}
	}

	Context "the machine scope" {
		It "is in scope without Machine and Hostname, and asks nothing about the machine type" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }) } }

			$definition.InScope | Should -BeTrue
			Should -Invoke Test-MachineTypeScope -Times 0 -Exactly
		}

		It "follows Test-MachineTypeScope for Machine" {
			$source = @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Machine = 'PC/Laptop' }) } }

			$script:MachineInScope = $true
			(Get-StartupTaskDefinitions -Configuration $source).InScope | Should -BeTrue

			$script:MachineInScope = $false
			(Get-StartupTaskDefinitions -Configuration $source).InScope | Should -BeFalse

			Should -Invoke Test-MachineTypeScope -Times 2 -Exactly -ParameterFilter { $Scope -eq 'PC/Laptop' }
		}

		It "is in scope when Hostname names this computer" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Hostname = $env:COMPUTERNAME }) } }

			$definition.InScope | Should -BeTrue
			($definition.Parameters.Hostname -join ',') | Should -Be $env:COMPUTERNAME
		}

		It "is in scope when Hostname names this computer in another casing, among others" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Hostname = @('Other-PC', $env:COMPUTERNAME.ToLowerInvariant()) }) }
			}

			$definition.InScope | Should -BeTrue
		}

		It "is out of scope when Hostname names only other computers" {
			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Hostname = @('Other-PC', 'Not-This-Computer') }) }
			}

			$definition.InScope | Should -BeFalse
		}

		It "needs both Machine and Hostname to match: <Case>" -ForEach @(
			@{ Case = 'both match'; MachineMatches = $true; HostnameMatches = $true; Expected = $true }
			@{ Case = 'only Machine matches'; MachineMatches = $true; HostnameMatches = $false; Expected = $false }
			@{ Case = 'only Hostname matches'; MachineMatches = $false; HostnameMatches = $true; Expected = $false }
			@{ Case = 'neither matches'; MachineMatches = $false; HostnameMatches = $false; Expected = $false }
		) {
			$script:MachineInScope = $MachineMatches
			$hostname = if ($HostnameMatches) { $env:COMPUTERNAME } else { 'Not-This-Computer' }

			$definition = Get-StartupTaskDefinitions -Configuration @{
				Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn'; Machine = 'PC'; Hostname = $hostname }) }
			}

			$definition.InScope | Should -Be $Expected
		}

		It "still returns a task that is out of scope or disabled, valid as it is" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup = @{
						Tasks = @(
							@{ Name = 'Elsewhere'; Trigger = 'SignIn'; Hostname = 'Not-This-Computer' }
							@{ Name = 'Parked'; Trigger = 'SignIn'; Enabled = $false }
						)
					}
				})

			$definitions.Count | Should -Be 2
			$definitions[0].Valid | Should -BeTrue
			$definitions[0].InScope | Should -BeFalse
			$definitions[1].Valid | Should -BeTrue
			$definitions[1].InScope | Should -BeTrue
			$definitions[1].Parameters.Enabled | Should -BeFalse
		}
	}

	Context "-Name and -Trigger" {
		BeforeEach {
			$script:TaskSource = @{
				Startup = @{
					Tasks = @(
						@{ Name = 'AtSignIn'; Trigger = 'SignIn' }
						@{ Name = 'AtWake'; Trigger = 'Wake' }
						@{ Name = 'AtBoth'; Trigger = @('Wake', 'SignIn') }
						@{ Name = 'InShell'; Trigger = 'TerminalOpen' }
					)
				}
			}
		}

		It "returns only the task named by -Name, whatever the casing" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Name atwake)

			($definitions.Name -join ',') | Should -Be 'AtWake'
		}

		It "returns every task named by -Name, in configuration order" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Name InShell, AtSignIn)

			($definitions.Name -join ',') | Should -Be 'AtSignIn,InShell'
		}

		It "returns nothing for a name no task has" {
			@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Name Nobody).Count | Should -Be 0
		}

		It "returns only the tasks that have the trigger named by -Trigger" {
			(@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Trigger SignIn).Name -join ',') | Should -Be 'AtSignIn,AtBoth'
			(@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Trigger Wake).Name -join ',') | Should -Be 'AtWake,AtBoth'
			(@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Trigger TerminalOpen).Name -join ',') | Should -Be 'InShell'
			@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Trigger Unlock).Count | Should -Be 0
		}

		It "applies -Name and -Trigger together" {
			@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Name AtBoth -Trigger Wake).Count | Should -Be 1
			@(Get-StartupTaskDefinitions -Configuration $script:TaskSource -Name AtSignIn -Trigger Wake).Count | Should -Be 0
		}

		It "still sees a repeated Name as repeated when -Name filters the first one out" {
			$source = @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }, @{ Name = 'Other'; Trigger = 'SignIn' }, @{ Name = 'MyTask'; Trigger = 'Wake' }) } }

			$definitions = @(Get-StartupTaskDefinitions -Configuration $source -Name MyTask -Trigger Wake)

			$definitions.Count | Should -Be 1
			$definitions[0].Valid | Should -BeFalse
		}
	}

	Context "the deprecated RepositoryUpdate.Startup keys" {
		It "adds no task while RepositoryUpdate.Startup is <Case>" -ForEach @(
			@{ Case = 'absent'; RepositoryUpdate = @{} }
			@{ Case = 'without Enabled'; RepositoryUpdate = @{ Startup = @{ Schedule = 'Daily' } } }
			@{ Case = 'switched off'; RepositoryUpdate = @{ Startup = @{ Enabled = $false } } }
		) {
			@(Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = $RepositoryUpdate }).Count | Should -Be 0
			Should -Invoke Resolve-RepositoryUpdateScope -Times 0 -Exactly
		}

		It "adds the RepositoryUpdate task while Startup.Enabled is on" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			@($definition).Count | Should -Be 1
			$definition.Name | Should -Be 'RepositoryUpdate'
			$definition.Legacy | Should -BeTrue
			$definition.Valid | Should -BeTrue
			$definition.InScope | Should -BeTrue
			($definition.Trigger -join ',') | Should -Be 'TerminalOpen'
			$definition.Parameters.Enabled | Should -BeTrue
			$definition.Parameters.Frequency | Should -Be 'OncePerDay'
			$definition.Parameters.DayStartHour | Should -Be 6
			$definition.Parameters.Elevation | Should -Be 'None'
		}

		It "updates every group when the scope says all" {
			$script:RepositoryScope = @{ All = $true; Groups = @() }

			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			$definition.Parameters.Command | Should -Be 'Update-Repositories -All -NoClone -Quiet'
		}

		It "updates every group when no scope can be resolved" {
			$script:RepositoryScope = $null

			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			$definition.Parameters.Command | Should -Be 'Update-Repositories -All -NoClone -Quiet'
		}

		It "updates only the groups of the scope" {
			$script:RepositoryScope = @{ All = $false; Groups = @('A', 'B') }

			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			$definition.Parameters.Command | Should -Be "Update-Repositories -Group 'A', 'B' -NoClone -Quiet"
		}

		It "quotes a group name that holds a quote, so the command still parses" {
			$script:RepositoryScope = @{ All = $false; Groups = @("Team's") }

			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			$definition.Parameters.Command | Should -Be "Update-Repositories -Group 'Team''s' -NoClone -Quiet"
			{ [scriptblock]::Create($definition.Parameters.Command) } | Should -Not -Throw
		}

		It "resolves the Bootstrap scope when Startup.Scope is absent" {
			Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } } | Out-Null

			Should -Invoke Resolve-RepositoryUpdateScope -Times 1 -Exactly -ParameterFilter { $Path -eq 'BootstrapConfig.RepositoryUpdateScope' }
		}

		It "resolves Startup.Scope when it is set" {
			Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Scope = @{ Default = 'Work' } } } } | Out-Null

			Should -Invoke Resolve-RepositoryUpdateScope -Times 1 -Exactly -ParameterFilter { $Path -eq 'RepositoryUpdate.Startup.Scope' }
		}

		It "runs once per day on the Daily schedule and carries DayStartHour" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'Daily'; DayStartHour = 4 } } }

			$definition.Parameters.Frequency | Should -Be 'OncePerDay'
			$definition.Parameters.DayStartHour | Should -Be 4
		}

		It "runs per interval on the Interval schedule and carries IntervalHours" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'interval'; IntervalHours = 8 } } }

			$definition.Parameters.Frequency | Should -Be 'Interval'
			$definition.Parameters.IntervalHours | Should -Be 8
		}

		It "runs once per day for a schedule it does not know" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'Weekly' } } }

			$definition.Valid | Should -BeTrue
			$definition.Parameters.Frequency | Should -Be 'OncePerDay'
		}

		It "falls back to 6 instead of failing for a DayStartHour of <Hour>" -ForEach @(
			@{ Hour = 24 }
			@{ Hour = -1 }
			@{ Hour = 'morning' }
		) {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; DayStartHour = $Hour } } }

			$definition.Valid | Should -BeTrue
			$definition.Parameters.DayStartHour | Should -Be 6
		}

		It "falls back to 24 instead of failing for IntervalHours that are no number" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true; Schedule = 'Interval'; IntervalHours = 'daily' } } }

			$definition.Valid | Should -BeTrue
			$definition.Parameters.IntervalHours | Should -Be 24
		}

		It "does not fall back for a configured task: the same DayStartHour is an error there" {
			$definition = Get-StartupTaskDefinitions -Configuration @{ Startup = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'TerminalOpen'; DayStartHour = 24 }) } }

			$definition.Valid | Should -BeFalse
		}

		It "adds the task after the configured ones" {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup          = @{ Tasks = @(@{ Name = 'MyTask'; Trigger = 'SignIn' }) }
					RepositoryUpdate = @{ Startup = @{ Enabled = $true } }
				})

			($definitions.Name -join ',') | Should -Be 'MyTask,RepositoryUpdate'
			$definitions[0].Legacy | Should -BeFalse
			$definitions[1].Legacy | Should -BeTrue
		}

		It "adds nothing when a task named <Spelling> is configured" -ForEach @(
			@{ Spelling = 'RepositoryUpdate' }
			@{ Spelling = 'repositoryupdate' }
		) {
			$definitions = @(Get-StartupTaskDefinitions -Configuration @{
					Startup          = @{ Tasks = @(@{ Name = $Spelling; Command = "Update-Repositories -Group 'Mine' -NoClone -Quiet"; Trigger = 'SignIn' }) }
					RepositoryUpdate = @{ Startup = @{ Enabled = $true } }
				})

			$definitions.Count | Should -Be 1
			$definitions[0].Legacy | Should -BeFalse
			$definitions[0].Valid | Should -BeTrue
			$definitions[0].Parameters.Command | Should -Be "Update-Repositories -Group 'Mine' -NoClone -Quiet"
			Should -Invoke Resolve-RepositoryUpdateScope -Times 0 -Exactly
		}

		It "is found by -Trigger TerminalOpen and -Name, and by no other trigger" {
			$source = @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

			@(Get-StartupTaskDefinitions -Configuration $source -Trigger TerminalOpen).Count | Should -Be 1
			@(Get-StartupTaskDefinitions -Configuration $source -Name RepositoryUpdate).Count | Should -Be 1
			@(Get-StartupTaskDefinitions -Configuration $source -Trigger SignIn).Count | Should -Be 0
		}

		Context "-IncludeLegacyDisabled" {
			It "adds the task, disabled, while Startup.Enabled is off" {
				$definition = Get-StartupTaskDefinitions -IncludeLegacyDisabled -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $false; Schedule = 'Interval'; IntervalHours = 8 } } }

				@($definition).Count | Should -Be 1
				$definition.Name | Should -Be 'RepositoryUpdate'
				$definition.Legacy | Should -BeTrue
				$definition.Valid | Should -BeTrue
				$definition.Parameters.Enabled | Should -BeFalse
				$definition.Parameters.Frequency | Should -Be 'Interval'
				$definition.Parameters.IntervalHours | Should -Be 8
			}

			It "adds the task, disabled, when the RepositoryUpdate section is absent" {
				$definition = Get-StartupTaskDefinitions -IncludeLegacyDisabled -Configuration @{}

				@($definition).Count | Should -Be 1
				$definition.Name | Should -Be 'RepositoryUpdate'
				$definition.Parameters.Enabled | Should -BeFalse
				$definition.Parameters.Frequency | Should -Be 'OncePerDay'
				$definition.Parameters.Command | Should -Be 'Update-Repositories -All -NoClone -Quiet'
			}

			It "keeps the task enabled while Startup.Enabled is on" {
				$definition = Get-StartupTaskDefinitions -IncludeLegacyDisabled -Configuration @{ RepositoryUpdate = @{ Startup = @{ Enabled = $true } } }

				@($definition).Count | Should -Be 1
				$definition.Parameters.Enabled | Should -BeTrue
			}

			It "still adds nothing when a task named RepositoryUpdate is configured" {
				$definitions = @(Get-StartupTaskDefinitions -IncludeLegacyDisabled -Configuration @{
						Startup = @{ Tasks = @(@{ Name = 'RepositoryUpdate'; Command = 'Do-Something'; Trigger = 'SignIn' }) }
					})

				$definitions.Count | Should -Be 1
				$definitions[0].Legacy | Should -BeFalse
			}
		}
	}
}
