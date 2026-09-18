#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\New-WindowClaimSet.ps1"
	. "$FunctionsPath\New-WorkspaceLayoutPipelineState.ps1"
	. "$FunctionsPath\Move-StableWindowEarly.ps1"

	# The desktop move and the logging, stubbed so Mock attaches in this scope instead of the
	# Window and Logging modules.
	function Move-WindowToVirtualDesktop { param([IntPtr]$WindowHandle, [int]$DesktopNumber) $true }
	function Test-LogVerbose { $false }
	function Write-LogDebug { param([string]$Message, [string]$Style) }

	function New-TestPipeline {
		param([pscustomobject]$Claims, [int]$DesktopOffset = 0)
		New-WorkspaceLayoutPipelineState -LayoutConfig @(@{ ProcessName = 'chrome'; DesktopNumber = 2 }) -Claims $Claims -DesktopOffset $DesktopOffset
	}
}

Describe "Move-StableWindowEarly" {
	BeforeEach {
		Mock Move-WindowToVirtualDesktop { $true }
		Mock Test-LogVerbose { $false }
		Mock Write-LogDebug { }

		$script:window = [PSCustomObject]@{ Handle = [IntPtr]0xA1; Title = 'Docs - Google Chrome' }
		$script:entry = @{ ProcessName = 'chrome'; DesktopNumber = 2 }
	}

	It "moves a claimable window to its entry's 0-based desktop index" {
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet)

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window

		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly -ParameterFilter {
			$WindowHandle -eq [IntPtr]0xA1 -and $DesktopNumber -eq 1
		}
	}

	It "adds the pipeline's desktop offset to the index" {
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet) -DesktopOffset 3

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window

		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly -ParameterFilter { $DesktopNumber -eq 4 }
	}

	It "does nothing for an entry without a desktop number" {
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet)

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry @{ ProcessName = 'chrome' } -Window $script:window

		Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly
	}

	It "leaves a protected window alone" {
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet -Protected @([IntPtr]0xA1))

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window

		Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly
	}

	It "leaves an existing window alone in alongside mode but moves it on a plain open" {
		$alongside = New-TestPipeline -Claims (New-WindowClaimSet -Existing @([IntPtr]0xA1) -SkipExisting)
		Move-StableWindowEarly -Pipeline $alongside -LayoutEntry $script:entry -Window $script:window
		Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly

		$plain = New-TestPipeline -Claims (New-WindowClaimSet -Existing @([IntPtr]0xA1))
		Move-StableWindowEarly -Pipeline $plain -LayoutEntry $script:entry -Window $script:window
		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly
	}

	It "leaves a window a per-desktop pass already placed alone" {
		$claims = New-WindowClaimSet
		[void]$claims.Excluded.Add([IntPtr]0xA1)
		$pipeline = New-TestPipeline -Claims $claims

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window

		Should -Invoke Move-WindowToVirtualDesktop -Times 0 -Exactly
	}

	It "swallows a failing move so the wait keeps going" {
		Mock Move-WindowToVirtualDesktop { throw 'RPC server unavailable' }
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet)

		{ Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window } | Should -Not -Throw
		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly
	}

	It "logs the early move with the display desktop number when verbose" {
		Mock Test-LogVerbose { $true }
		$pipeline = New-TestPipeline -Claims (New-WindowClaimSet) -DesktopOffset 3

		Move-StableWindowEarly -Pipeline $pipeline -LayoutEntry $script:entry -Window $script:window

		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -match 'Early move' -and $Message -match 'Desktop 5' }
	}
}
