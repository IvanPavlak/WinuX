#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-WorkspaceLayoutTimings.ps1"
}

Describe "Get-WorkspaceLayoutTimings" {
	BeforeEach {
		# Module-scoped in production; dot-sourced here, the function resolves $script: to this file.
		$script:LastWorkspaceLayoutTimings = $null
	}

	It "returns nothing before any layout has run in the session" {
		Get-WorkspaceLayoutTimings | Should -BeNullOrEmpty
	}

	It "returns the record the last layout run published, unchanged" {
		$recordedAt = [DateTimeOffset]::Now
		$script:LastWorkspaceLayoutTimings = [PSCustomObject]@{
			Workspace     = 'MyWorkspace'
			LayoutFile    = 'C:\Layouts\PC\MyWorkspace_PC.psd1'
			Alongside     = $false
			DesktopOffset = 0
			Attempts      = 2
			Outcome       = 'Applied'
			TotalSeconds  = 12.3
			Phases        = [ordered]@{ Preamble = 0.4; Wait = 8.1; Snap = 3.0 }
			RecordedAt    = $recordedAt
		}

		$result = Get-WorkspaceLayoutTimings

		$result.Workspace | Should -Be 'MyWorkspace'
		$result.Attempts | Should -Be 2
		$result.Outcome | Should -Be 'Applied'
		$result.Phases.Wait | Should -Be 8.1
		$result.RecordedAt | Should -Be $recordedAt
	}

	It "reflects every replacement - the value describes the most recent run only" {
		$script:LastWorkspaceLayoutTimings = [PSCustomObject]@{ Workspace = 'First'; Phases = [ordered]@{ Wait = 1.0 } }
		(Get-WorkspaceLayoutTimings).Workspace | Should -Be 'First'

		$script:LastWorkspaceLayoutTimings = [PSCustomObject]@{ Workspace = 'Second'; Phases = [ordered]@{ Wait = 2.0 } }
		(Get-WorkspaceLayoutTimings).Workspace | Should -Be 'Second'
	}
}
