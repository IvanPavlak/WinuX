#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Docker-Cleanup.ps1"
}

Describe "Docker-Cleanup" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
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

	It "warns and stops when the Docker daemon is not running" {
		Mock docker {
			param([Parameter(ValueFromRemainingArguments = $true)]$Args)
			$global:LASTEXITCODE = 1
		}

		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Invoke-Expression -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'not running' }
	}

	It "warns when no cleanup actions are configured" {
		$script:Configuration = [PSCustomObject]@{ DockerCleanupActions = @() }

		Docker-Cleanup

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'No cleanup actions' }
	}

	It "warns instead of offering a blank menu entry when the configuration key is absent" {
		# @($null).Count is 1, so an unwrapped guard would pass and build a menu with
		# one empty option - the realistic case for a fork that drops the key entirely
		$script:Configuration = [PSCustomObject]@{}

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
}
