#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-VSCodeWorkspace.ps1"
	. "$AppFunctionsPath\Start-VSCodeDetached.ps1"
	. "$AppFunctionsPath\Get-VSCodeWorkspaceNames.ps1"
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Open-VSCodeWorkspace" {
	BeforeEach {
		$script:workspacesDir = Join-Path $TestDrive "Workspaces"
		New-Item -ItemType Directory -Path $script:workspacesDir -Force | Out-Null
		New-Item -ItemType File -Path (Join-Path $script:workspacesDir "Alpha.code-workspace") -Force | Out-Null
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ VSCodeWorkspaces = $script:workspacesDir } } }

		Mock Write-Host { }
		Mock Get-VSCodeWorkspaceNames { @('Alpha') }
		Mock Resolve-Selection { $InputObject }
		Mock Test-ProjectAlreadyOpen { $false }
		Mock Start-VSCodeDetached { }
	}

	AfterEach {
		Remove-Item -Path $script:workspacesDir -Recurse -Force -ErrorAction SilentlyContinue
	}

	It "opens the workspace file detached in a new window and returns its name" {
		$result = Open-VSCodeWorkspace -VSCodeWorkspace Alpha

		$expectedFile = Join-Path $script:workspacesDir "Alpha.code-workspace"
		Should -Invoke Test-ProjectAlreadyOpen -Times 1 -Exactly -ParameterFilter {
			$ProjectName -eq 'Alpha (Workspace)' -and $ProcessName -eq 'Code'
		}
		Should -Invoke Start-VSCodeDetached -Times 1 -Exactly -ParameterFilter {
			$ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq "`"$expectedFile`""
		}
		@($result) | Should -Be @('Alpha')
	}

	It "does not relaunch a workspace that already has a window but still reports it" {
		Mock Test-ProjectAlreadyOpen { $true }

		$result = Open-VSCodeWorkspace -VSCodeWorkspace Alpha

		Should -Invoke Start-VSCodeDetached -Times 0
		@($result) | Should -Be @('Alpha')
	}

	It "reports a missing workspace file and leaves it out of the result" {
		Mock Get-VSCodeWorkspaceNames { @('Alpha', 'Missing') }

		$result = Open-VSCodeWorkspace -VSCodeWorkspace Alpha, Missing

		Should -Invoke Start-VSCodeDetached -Times 1 -Exactly
		@($result) | Should -Be @('Alpha')
	}

	It "reports a failed launch and leaves the workspace out of the result" {
		Mock Start-VSCodeDetached { throw 'code is not installed' }

		$result = Open-VSCodeWorkspace -VSCodeWorkspace Alpha

		@($result) | Should -BeNullOrEmpty
	}

	It "returns early when the workspaces folder does not exist" {
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ VSCodeWorkspaces = (Join-Path $TestDrive "nowhere") } } }

		$result = Open-VSCodeWorkspace -VSCodeWorkspace Alpha

		Should -Invoke Start-VSCodeDetached -Times 0
		@($result) | Should -BeNullOrEmpty
	}

	It "returns early when nothing is selected" {
		Mock Resolve-Selection { $null }

		$result = Open-VSCodeWorkspace

		Should -Invoke Start-VSCodeDetached -Times 0
		@($result) | Should -BeNullOrEmpty
	}
}
