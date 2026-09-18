#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\New-WindowClaimSet.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\New-WorkspaceLayoutPipelineState.ps1")
}

Describe "New-WorkspaceLayoutPipelineState" {
	BeforeEach {
		$script:claims = New-WindowClaimSet -Existing @(4)
		$script:layout = @(@{ ProcessName = 'Code'; DesktopNumber = 1 }, @{ ProcessName = 'chrome'; DesktopNumber = 2 })
	}

	It "carries every input it was given" {
		$reset = { param([string]$Reason) }
		$record = { param([string]$Phase) }
		$monitors = @([PSCustomObject]@{ DeviceName = '\\.\DISPLAY1' })
		$monitorConfig = @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = 'One' } } }

		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims -MonitorInfo $monitors -MonitorConfig $monitorConfig `
			-DesktopOffset 3 -DesktopCount 2 -Alongside -ZoneReset $reset -RecordPhase $record -SpinnerActive

		$pipeline.LayoutConfig.Count | Should -Be 2
		$pipeline.Claims | Should -Be $script:claims
		$pipeline.MonitorInfo.Count | Should -Be 1
		$pipeline.MonitorConfig.ContainsKey('Primary') | Should -BeTrue
		$pipeline.DesktopOffset | Should -Be 3
		$pipeline.DesktopCount | Should -Be 2
		$pipeline.Alongside | Should -BeTrue
		$pipeline.ZoneReset | Should -Be $reset
		$pipeline.RecordPhase | Should -Be $record
		$pipeline.SpinnerActive | Should -BeTrue
	}

	It "defaults to a plain open with no offset, no spinner and no zone reset" {
		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims

		$pipeline.DesktopOffset | Should -Be 0
		$pipeline.DesktopCount | Should -Be 0
		$pipeline.Alongside | Should -BeFalse
		$pipeline.SpinnerActive | Should -BeFalse
		$pipeline.ZoneReset | Should -BeNullOrEmpty
		$pipeline.MonitorInfo | Should -BeNullOrEmpty
		$pipeline.MonitorConfig | Should -BeNullOrEmpty
	}

	It "starts every live tally empty, typed for the tail that reads it" {
		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims

		$pipeline.PipelinedDesktops.Count | Should -Be 0
		$pipeline.PipelinedEntryKeys.Count | Should -Be 0
		$pipeline.PipelinedResults.Count | Should -Be 0
		$pipeline.PipelinedSnapFailures.Count | Should -Be 0

		# The tallies are live: what a per-desktop pass adds is what the tail sees.
		$pipeline.PipelinedDesktops[2] = $true
		[void]$pipeline.PipelinedEntryKeys.Add('2|||chrome|')
		$pipeline.PipelinedResults.Add([PSCustomObject]@{ Status = 'Configured' })
		$pipeline.PipelinedSnapFailures.Add(@{ Handle = 8 })

		$pipeline.PipelinedDesktops.Count | Should -Be 1
		$pipeline.PipelinedEntryKeys.Contains('2|||chrome|') | Should -BeTrue
		$pipeline.PipelinedResults.Count | Should -Be 1
		$pipeline.PipelinedSnapFailures.Count | Should -Be 1
	}

	It "substitutes a no-op phase recorder when none is given" {
		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $script:layout -Claims $script:claims

		$pipeline.RecordPhase | Should -Not -BeNullOrEmpty
		{ & $pipeline.RecordPhase 'Wait' } | Should -Not -Throw
	}

	It "accepts an empty layout" {
		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig @() -Claims $script:claims

		@($pipeline.LayoutConfig).Count | Should -Be 0
	}
}
