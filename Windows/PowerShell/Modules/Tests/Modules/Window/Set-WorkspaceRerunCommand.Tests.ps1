#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WorkspaceRerunCommand.ps1"
	. "$FunctionsPath\Get-WorkspaceRerunCommand.ps1"
}

Describe "Set-WorkspaceRerunCommand and Get-WorkspaceRerunCommand" {
	BeforeEach {
		$script:WorkspaceRerunCommand = $null
		[Environment]::SetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', $null, 'Process')
	}

	It "returns nothing when no command has been recorded" {
		Get-WorkspaceRerunCommand | Should -BeNullOrEmpty
	}

	It "records a command and reads it back verbatim" {
		Set-WorkspaceRerunCommand -Command "Open-Workspace -Workspace 'WinuX', 'Server' -Alongside"

		Get-WorkspaceRerunCommand | Should -Be "Open-Workspace -Workspace 'WinuX', 'Server' -Alongside"
	}

	It "overwrites a previous record" {
		Set-WorkspaceRerunCommand -Command 'first'
		Set-WorkspaceRerunCommand -Command 'second'

		Get-WorkspaceRerunCommand | Should -Be 'second'
	}

	It "clears the record with -Clear" {
		Set-WorkspaceRerunCommand -Command 'something'
		Set-WorkspaceRerunCommand -Clear

		Get-WorkspaceRerunCommand | Should -BeNullOrEmpty
	}

	It "treats an empty or whitespace command as a clear" {
		Set-WorkspaceRerunCommand -Command 'something'
		Set-WorkspaceRerunCommand -Command '   '

		Get-WorkspaceRerunCommand | Should -BeNullOrEmpty

		Set-WorkspaceRerunCommand -Command 'again'
		Set-WorkspaceRerunCommand -Command $null

		Get-WorkspaceRerunCommand | Should -BeNullOrEmpty
	}

	It "never touches the process environment" {
		# The whole point of the store: a child process spawned by the open must not inherit it.
		Set-WorkspaceRerunCommand -Command "Open-Workspace -Workspace 'WinuX'"

		[Environment]::GetEnvironmentVariable('WORKSPACE_RERUN_COMMAND', 'Process') | Should -BeNullOrEmpty
	}
}
