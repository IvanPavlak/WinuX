#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Workflow\Functions\Resolve-TrackedWorkspaceWindow.ps1")

	function New-TestWindow {
		param($Handle, $ProcessId, $ProcessName, $Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; ProcessId = $ProcessId; ProcessName = $ProcessName; Title = $Title }
	}

	function New-TestRecord {
		param($Handle, $ProcessId = 0, $ProcessName = '', $Title = '')
		[ordered]@{ Handle = [int64]$Handle; ProcessId = [int64]$ProcessId; ProcessName = $ProcessName; Title = $Title }
	}
}

Describe "Resolve-TrackedWorkspaceWindow" {
	It "matches a live recorded handle exactly" {
		$live = @((New-TestWindow -Handle 10 -ProcessId 1 -ProcessName 'firefox' -Title 'Anything'))

		$resolved = Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 10 -ProcessId 1 -ProcessName 'firefox' -Title 'Other') -LiveWindows $live

		[int64]$resolved.Window.Handle | Should -Be 10
		$resolved.Exact | Should -BeTrue
	}

	It "re-resolves by process id when that process has a single live window" {
		$live = @((New-TestWindow -Handle 20 -ProcessId 2 -ProcessName 'Obsidian' -Title 'Renamed'))

		$resolved = Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 11 -ProcessId 2 -ProcessName 'Obsidian' -Title 'Vault') -LiveWindows $live

		[int64]$resolved.Window.Handle | Should -Be 20
		$resolved.Exact | Should -BeFalse
	}

	It "skips the process id step when the process hosts several windows" {
		$live = @(
			(New-TestWindow -Handle 20 -ProcessId 2 -ProcessName 'firefox' -Title 'Mail'),
			(New-TestWindow -Handle 21 -ProcessId 2 -ProcessName 'firefox' -Title 'Calendar')
		)

		Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 11 -ProcessId 2 -ProcessName 'firefox' -Title 'Gone') -LiveWindows $live |
			Should -BeNullOrEmpty
	}

	It "still falls through to the exact title among several windows of one process" {
		$live = @(
			(New-TestWindow -Handle 20 -ProcessId 2 -ProcessName 'firefox' -Title 'Mail'),
			(New-TestWindow -Handle 21 -ProcessId 2 -ProcessName 'firefox' -Title 'Calendar')
		)

		$resolved = Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 11 -ProcessId 2 -ProcessName 'firefox' -Title 'Calendar') -LiveWindows $live

		[int64]$resolved.Window.Handle | Should -Be 21
		$resolved.Exact | Should -BeFalse
	}

	It "resolves a Windows Terminal record by handle only" {
		# Same process, same generic title - and still not the recorded window.
		$live = @((New-TestWindow -Handle 30 -ProcessId 3 -ProcessName 'WindowsTerminal' -Title 'PowerShell'))

		Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 12 -ProcessId 3 -ProcessName 'WindowsTerminal' -Title 'PowerShell') -LiveWindows $live |
			Should -BeNullOrEmpty
	}

	It "never re-resolves a record that names no process" {
		$live = @((New-TestWindow -Handle 40 -ProcessId 4 -ProcessName 'Obsidian' -Title 'Vault'))

		Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 13 -Title 'Vault') -LiveWindows $live |
			Should -BeNullOrEmpty
	}

	It "returns null when there are no live windows" {
		Resolve-TrackedWorkspaceWindow -Record (New-TestRecord -Handle 14 -ProcessId 5 -ProcessName 'Code' -Title 'Editor') -LiveWindows @() |
			Should -BeNullOrEmpty
	}
}
