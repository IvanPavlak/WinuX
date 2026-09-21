#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Invoke-ObsidianCli.ps1"
	. "$AppFunctionsPath\Wait-ObsidianCli.ps1"
	. "$AppFunctionsPath\Invoke-ObsidianWorkspaceLoad.ps1"
	. "$AppFunctionsPath\Complete-ObsidianWorkspaceLoad.ps1"

	function script:New-LoadResult {
		param([bool]$Loaded, [string]$Refusal)
		[PSCustomObject]@{
			Loaded  = $Loaded
			Refusal = $(if ($Loaded) { $null } else { $Refusal })
			Message = $(if ($Loaded) { $null } else { "Obsidian workspace [Server] not loaded => $Refusal Run [Enable-ObsidianCli] with Obsidian closed." })
		}
	}
}

Describe "Complete-ObsidianWorkspaceLoad" {
	BeforeEach {
		# Answers for successive load attempts; the last one repeats.
		$script:loadAnswers = @((New-LoadResult -Loaded $true))
		$script:loadCalls = 0
		Mock Invoke-ObsidianWorkspaceLoad {
			$index = [math]::Min($script:loadCalls, $script:loadAnswers.Count - 1)
			$script:loadCalls++
			$script:loadAnswers[$index]
		}
		Mock Wait-ObsidianCli { $true }
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }
	}

	It "loads first and never polls when the load lands, cold start or not" {
		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'MyVault' -Name 'Server' -ColdStart | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 0
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'C:\Obsidian.com' -and $Vault -eq 'MyVault' -and $Name -eq 'Server' }
		Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]Server[]]*' }
	}

	It "keeps the first cold-start attempt silent, because a premature one is expected" {
		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeTrue

		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly -ParameterFilter { $Silent }
	}

	It "lets an already-running load report its own refusal, no silence and no poll" {
		$script:loadAnswers = @((New-LoadResult -Loaded $false -Refusal 'The CLI is unable to find Obsidian'))

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'DSA' | Should -BeFalse

		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly -ParameterFilter { -not $Silent }
		Should -Invoke Wait-ObsidianCli -Times 0
		# Invoke-ObsidianWorkspaceLoad already warned; nothing is repeated here.
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "polls and tries once more when a cold start's first attempt finds Obsidian not yet up" {
		$script:loadAnswers = @(
			(New-LoadResult -Loaded $false -Refusal 'The CLI is unable to find Obsidian'),
			(New-LoadResult -Loaded $true)
		)

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $CliPath -eq 'C:\Obsidian.com' -and $Vault -eq 'V' -and $TimeoutSeconds -eq 10 }
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 2 -Exactly
		# The retry is the reported one.
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly -ParameterFilter { -not $Silent }
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogSuccess -Times 1 -Exactly
	}

	It "honours a caller's readiness budget on that poll" {
		$script:loadAnswers = @(
			(New-LoadResult -Loaded $false -Refusal 'The CLI is unable to find Obsidian'),
			(New-LoadResult -Loaded $true)
		)

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart -TimeoutSeconds 30 | Should -BeTrue

		Should -Invoke Wait-ObsidianCli -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 30 }
	}

	It "warns and stops when the CLI never answers after a not-yet-up first attempt" {
		$script:loadAnswers = @((New-LoadResult -Loaded $false -Refusal 'The CLI is unable to find Obsidian'))
		Mock Wait-ObsidianCli { $false }

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeFalse

		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*did not answer*[[]Server[]]*' }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "reports a final refusal on a cold start once, without polling or retrying" {
		$script:loadAnswers = @((New-LoadResult -Loaded $false -Refusal 'Command line interface is not enabled'))

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeFalse

		Should -Invoke Wait-ObsidianCli -Times 0
		Should -Invoke Invoke-ObsidianWorkspaceLoad -Times 1 -Exactly
		# The silent first attempt handed back its message; this is where it is written, once.
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*not loaded*not enabled*' }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "stays silent about success when the retry is refused too" {
		$script:loadAnswers = @(
			(New-LoadResult -Loaded $false -Refusal 'The CLI is unable to find Obsidian'),
			(New-LoadResult -Loaded $false -Refusal 'Command line interface is not enabled')
		)

		Complete-ObsidianWorkspaceLoad -CliPath 'C:\Obsidian.com' -Vault 'V' -Name 'Server' -ColdStart | Should -BeFalse

		# The loud retry reported its own refusal inside Invoke-ObsidianWorkspaceLoad.
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogSuccess -Times 0
	}
}
