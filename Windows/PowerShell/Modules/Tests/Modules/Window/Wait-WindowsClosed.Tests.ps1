#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Wait-WindowsClosed.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Clear-WindowCache { }

	function New-TestWindow {
		param($Handle, $Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title }
	}
}

Describe "Wait-WindowsClosed" {
	BeforeEach {
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }
		Mock Get-WindowHandle { @() }
	}

	It "returns immediately when handed nothing to wait on" {
		Wait-WindowsClosed -Window @() | Should -BeNullOrEmpty

		Should -Invoke Get-WindowHandle -Times 0
	}

	It "reports nothing left when every window has gone" {
		$posted = @((New-TestWindow -Handle 101 -Title 'GitHub'), (New-TestWindow -Handle 203 -Title 'Repo'))

		Wait-WindowsClosed -Window $posted | Should -BeNullOrEmpty
	}

	It "reports the windows still open once it gives up" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 203 -Title 'Repo')) }
		$posted = @((New-TestWindow -Handle 101 -Title 'GitHub'), (New-TestWindow -Handle 203 -Title 'Repo'))

		$refused = @(Wait-WindowsClosed -Window $posted -TimeoutMilliseconds 0)

		$refused.Count | Should -Be 1
		$refused[0].Title | Should -Be 'Repo'
	}

	It "stops as soon as the windows go, without waiting out the timeout" {
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -eq 1) { @((New-TestWindow -Handle 101 -Title 'GitHub')) } else { @() }
		}

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) | Should -BeNullOrEmpty

		$script:pollCount | Should -Be 2
	}

	It "invalidates the window cache before every poll" {
		# Without this the same pre-close snapshot is read each time and every window looks
		# like it refused to close.
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -lt 3) { @((New-TestWindow -Handle 101 -Title 'GitHub')) } else { @() }
		}

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) | Out-Null

		Should -Invoke Clear-WindowCache -Times 3
	}

	It "matches by handle, not by a replacement window of the same application" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 999 -Title 'GitHub')) }

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) -TimeoutMilliseconds 0 | Should -BeNullOrEmpty
	}

	It "ignores null entries in the input" {
		{ Wait-WindowsClosed -Window @($null, (New-TestWindow -Handle 101 -Title 'GitHub')) } | Should -Not -Throw
	}
}
