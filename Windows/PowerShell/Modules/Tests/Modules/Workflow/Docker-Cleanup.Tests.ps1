#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Docker-Cleanup.ps1"

	function DockerWizard { param([switch]$PassThru) }
}

Describe "Docker-Cleanup" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			DockerCleanupActions = @(
				@{ Name                = "Delete all volumes";
					Command             = 'docker volume ls -q | ForEach-Object { docker volume rm $_ }';
					ConfirmationMessage = "Are you sure you want to delete ALL volumes?"
				}
				@{ Name    = "Harmless action";
					Command = 'docker version'
				}
			)
		}

		Mock Write-Host { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Get-Command { [PSCustomObject]@{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
		Mock Invoke-Expression { $global:LASTEXITCODE = 0 }

		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$global:LASTEXITCODE = 0
		}

		Mock Resolve-Selection {
			if ($ConfirmationMessage) {
				return "Yes"
			}
			return "Delete all volumes"
		}
	}

	It "runs the selected destructive action only after an explicit Yes" {
		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 1 -ParameterFilter {
			$ConfirmationMessage -eq "Are you sure you want to delete ALL volumes?"
		}
		Should -Invoke Invoke-Expression -Times 1 -ParameterFilter {
			$Command -eq 'docker volume ls -q | ForEach-Object { docker volume rm $_ }'
		}
		Should -Invoke Write-LogSuccess -Times 1
	}

	It "does not run the action when the confirmation is declined" {
		Mock Resolve-Selection {
			if ($ConfirmationMessage) {
				return "No"
			}
			return "Delete all volumes"
		}

		Docker-Cleanup

		Should -Invoke Invoke-Expression -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'Cancelled' }
	}

	It "runs an action without a ConfirmationMessage immediately" {
		Mock Resolve-Selection { "Harmless action" }

		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 1 -Exactly
		Should -Invoke Invoke-Expression -Times 1 -ParameterFilter { $Command -eq 'docker version' }
	}

	It "accepts a configured action name directly while keeping the safeguard" {
		Mock Resolve-Selection {
			if ($ConfirmationMessage) {
				return "Yes"
			}
			return $InputObject
		}

		Docker-Cleanup "Delete all volumes"

		Should -Invoke Resolve-Selection -Times 1 -ParameterFilter { $InputObject -eq "Delete all volumes" }
		Should -Invoke Invoke-Expression -Times 1
	}

	Context "when the Docker daemon is not running" {
		BeforeEach {
			Mock docker {
				param([Parameter(ValueFromRemainingArguments = $true)]$Args)
				$global:LASTEXITCODE = 1
			}

			Mock DockerWizard { [PSCustomObject]@{ Success = $true; ComposeFilePath = $null } }

			Mock Resolve-Selection {
				if ($PromptMessage -match 'not running') {
					return "Yes"
				}
				if ($ConfirmationMessage) {
					return "Yes"
				}
				return "Delete all volumes"
			}
		}

		It "asks by default and starts Docker through DockerWizard before showing the menu" {
			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				$PromptMessage -match 'not running' -and $DefaultOptionIndex -eq 1
			}
			Should -Invoke DockerWizard -Times 1 -Exactly -ParameterFilter { $PassThru }
			Should -Invoke Invoke-Expression -Times 1
		}

		It "starts nothing and shows no menu when the start prompt is declined" {
			Mock Resolve-Selection {
				if ($PromptMessage -match 'not running') {
					return "No"
				}
				return "Delete all volumes"
			}

			Docker-Cleanup

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Resolve-Selection -Times 1 -Exactly
			Should -Invoke Invoke-Expression -Times 0
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'not running' }
		}

		It "starts Docker without asking when DockerCleanupStartMode is Always" {
			$global:Configuration | Add-Member -NotePropertyName DockerCleanupStartMode -NotePropertyValue "Always"

			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 0 -ParameterFilter { $PromptMessage -match 'not running' }
			Should -Invoke DockerWizard -Times 1 -Exactly
			Should -Invoke Invoke-Expression -Times 1
		}

		It "warns and returns without starting Docker when DockerCleanupStartMode is Never" {
			$global:Configuration | Add-Member -NotePropertyName DockerCleanupStartMode -NotePropertyValue "Never"

			Docker-Cleanup

			Should -Invoke DockerWizard -Times 0
			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke Invoke-Expression -Times 0
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'not running' }
		}

		It "treats an unknown DockerCleanupStartMode like Ask" {
			$global:Configuration | Add-Member -NotePropertyName DockerCleanupStartMode -NotePropertyValue "Sometimes"

			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { $PromptMessage -match 'not running' }
			Should -Invoke DockerWizard -Times 1 -Exactly
		}

		It "shows no menu and runs nothing when DockerWizard fails to start Docker" {
			Mock DockerWizard { [PSCustomObject]@{ Success = $false; ComposeFilePath = $null } }

			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 0 -ParameterFilter { $OptionList -contains "Delete all volumes" }
			Should -Invoke Invoke-Expression -Times 0
			Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match 'could not be started' }
		}
	}

	It "warns when no cleanup actions are configured" {
		$global:Configuration = [PSCustomObject]@{ DockerCleanupActions = @() }

		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'No cleanup actions' }
	}

	It "warns instead of offering a blank menu entry when the configuration key is absent" {
		# @($null).Count is 1, so an unwrapped guard would pass and build a menu with
		# one empty option - the realistic case for a fork that drops the key entirely
		$global:Configuration = [PSCustomObject]@{}

		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Invoke-Expression -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'No cleanup actions' }
	}

	It "reports a failing action instead of claiming success" {
		Mock Invoke-Expression { $global:LASTEXITCODE = 1 }

		Docker-Cleanup

		Should -Invoke Write-LogSuccess -Times 0
		Should -Invoke Write-LogError -Times 1
	}

	It "offers an All option on a multi-select menu" {
		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
			$AllowMultipleSelections -and $OptionList[-1] -eq "All" -and $OptionList -contains "Delete all volumes"
		}
	}

	Context "previews, All and multi-select" {
		BeforeEach {
			$global:Configuration = [PSCustomObject]@{
				DockerCleanupActions = @(
					@{ Name                = "Stop all containers";
						Description         = "Stops every running container.";
						Command             = 'cmd-stop';
						PreviewCommand      = 'preview-stop';
						ConfirmationMessage = "Stop them?"
					}
					@{ Name                = "Delete all volumes";
						Command             = 'cmd-volumes';
						PreviewCommand      = 'preview-volumes';
						ConfirmationMessage = "Delete them?"
					}
					@{ Name    = "Custom action";
						Command = 'cmd-custom'
					}
				)
			}

			# Every Invoke-Expression call is recorded in order, so a test can tell
			# previews from commands and check the order the commands ran in
			$global:DockerCleanupTestCalls = [System.Collections.Generic.List[string]]::new()
			$global:DockerCleanupTestPreviews = @{
				'preview-stop'    = @("web (nginx)", "db (postgres)")
				'preview-volumes' = @("pgdata (local)")
			}

			Mock Invoke-Expression {
				$global:DockerCleanupTestCalls.Add($Command)
				$global:LASTEXITCODE = 0
				if ($global:DockerCleanupTestPreviews.ContainsKey($Command)) {
					$global:DockerCleanupTestPreviews[$Command]
				}
			}

			Mock Write-LogList { }

			$global:DockerCleanupTestPick = @("All")
			Mock Resolve-Selection {
				if ($ConfirmationMessage) {
					return "Yes"
				}
				return $global:DockerCleanupTestPick
			}
		}

		AfterEach {
			Remove-Variable -Name DockerCleanupTestCalls, DockerCleanupTestPreviews, DockerCleanupTestPick -Scope Global -ErrorAction SilentlyContinue
		}

		It "runs every action for All, previewing all of them before the first command" {
			Docker-Cleanup

			$global:DockerCleanupTestCalls | Should -Be @('preview-stop', 'preview-volumes', 'cmd-stop', 'cmd-volumes', 'cmd-custom')
		}

		It "lists each action's preview items before the confirmation" {
			Docker-Cleanup

			Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter { $Items -contains "web (nginx)" -and $Items -contains "db (postgres)" }
			Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter { $Items -contains "pgdata (local)" }
			Should -Invoke Write-LogStep -ParameterFilter { $Message -match 'Stops every running container' }
		}

		It "runs a multi-selection in configuration order, not selection order" {
			$global:DockerCleanupTestPick = @("Custom action", "Stop all containers")

			Docker-Cleanup

			@($global:DockerCleanupTestCalls | Where-Object { $_ -like 'cmd-*' }) | Should -Be @('cmd-stop', 'cmd-custom')
		}

		It "asks one confirmation for several actions" {
			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { $ConfirmationMessage -match '3 actions' }
			Should -Invoke Resolve-Selection -Times 2 -Exactly
		}

		It "uses the action's own confirmation message when only one action remains" {
			$global:DockerCleanupTestPick = @("Delete all volumes")

			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { $ConfirmationMessage -eq "Delete them?" }
		}

		It "skips an action whose preview lists nothing and still runs the rest" {
			$global:DockerCleanupTestPreviews['preview-stop'] = @("", "  ")

			Docker-Cleanup

			$global:DockerCleanupTestCalls | Should -Not -Contain 'cmd-stop'
			$global:DockerCleanupTestCalls | Should -Contain 'cmd-volumes'
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'Stop all containers - nothing to do' }
		}

		It "asks nothing and runs nothing when every selected preview is empty" {
			$global:DockerCleanupTestPreviews = @{}
			$global:DockerCleanupTestPick = @("Stop all containers", "Delete all volumes")

			Docker-Cleanup

			Should -Invoke Resolve-Selection -Times 0 -ParameterFilter { $ConfirmationMessage }
			@($global:DockerCleanupTestCalls | Where-Object { $_ -like 'cmd-*' }).Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'Nothing to do' }
		}

		It "keeps an action without a PreviewCommand and runs it" {
			$global:DockerCleanupTestPick = @("Custom action")

			Docker-Cleanup

			$global:DockerCleanupTestCalls | Should -Be @('cmd-custom')
			Should -Invoke Resolve-Selection -Times 0 -ParameterFilter { $ConfirmationMessage }
		}

		It "runs nothing when the combined confirmation is declined" {
			Mock Resolve-Selection {
				if ($ConfirmationMessage) {
					return "No"
				}
				return @("All")
			}

			Docker-Cleanup

			@($global:DockerCleanupTestCalls | Where-Object { $_ -like 'cmd-*' }).Count | Should -Be 0
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'Cancelled' }
		}

		It "keeps running the remaining actions after one fails" {
			Mock Invoke-Expression {
				$global:DockerCleanupTestCalls.Add($Command)
				$global:LASTEXITCODE = if ($Command -eq 'cmd-stop') { 1 } else { 0 }
				if ($global:DockerCleanupTestPreviews.ContainsKey($Command)) {
					$global:DockerCleanupTestPreviews[$Command]
				}
			}

			Docker-Cleanup

			$global:DockerCleanupTestCalls | Should -Contain 'cmd-volumes'
			$global:DockerCleanupTestCalls | Should -Contain 'cmd-custom'
			Should -Invoke Write-LogError -Times 1 -Exactly
			Should -Invoke Write-LogSuccess -Times 2 -Exactly
		}

		It "passes -Action All straight to the menu resolver" {
			Mock Resolve-Selection {
				if ($ConfirmationMessage) {
					return "Yes"
				}
				return $InputObject
			}

			Docker-Cleanup All

			Should -Invoke Resolve-Selection -Times 1 -ParameterFilter { $InputObject -contains "All" }
			@($global:DockerCleanupTestCalls | Where-Object { $_ -like 'cmd-*' }) | Should -Be @('cmd-stop', 'cmd-volumes', 'cmd-custom')
		}

		It "accepts several action names through -Action" {
			Mock Resolve-Selection {
				if ($ConfirmationMessage) {
					return "Yes"
				}
				return $InputObject
			}

			Docker-Cleanup "Delete all volumes", "Stop all containers"

			@($global:DockerCleanupTestCalls | Where-Object { $_ -like 'cmd-*' }) | Should -Be @('cmd-stop', 'cmd-volumes')
		}
	}
}
