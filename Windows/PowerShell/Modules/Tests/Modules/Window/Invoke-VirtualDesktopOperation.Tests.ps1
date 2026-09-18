#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
}

Describe "Invoke-VirtualDesktopOperation" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		$null = New-FakeVirtualDesktopSession -DesktopCount 3 -CurrentIndex 1
	}

	It "returns what the operation returns" {
		Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } | Should -Be 3
	}

	It "throws one clear error when the VirtualDesktop module is not available, without running the operation" {
		$null = New-FakeVirtualDesktopSession -ModuleUnavailable
		$script:ran = $false

		{ Invoke-VirtualDesktopOperation -Operation { $script:ran = $true } } | Should -Throw '*VirtualDesktop module is not available*'
		$script:ran | Should -BeFalse
	}

	It "recovers a stale session once: resets the state and retries after an RPC failure" {
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1

		Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } | Should -Be 3
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
	}

	It "throws the RPC error once the attempts are exhausted" {
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 10
		Mock Reset-VirtualDesktopState { $global:FakeVirtualDesktop.ResetCount++; $true }

		{ Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -MaxAttempts 3 } | Should -Throw '*0x800706BA*'
		$global:FakeVirtualDesktop.ResetCount | Should -Be 2
	}

	It "rethrows a non-RPC error at once, without resetting anything" {
		{ Invoke-VirtualDesktopOperation -Operation { throw 'TYPE_E_ELEMENTNOTFOUND' } } | Should -Throw '*TYPE_E_ELEMENTNOTFOUND*'
		$global:FakeVirtualDesktop.ResetCount | Should -Be 0
		Should -Invoke Start-Sleep -Times 0
	}

	It "backs off exponentially between attempts" {
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 2
		Mock Reset-VirtualDesktopState { $true }

		Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -MaxAttempts 3 -InitialDelayMs 100 | Should -Be 3
		Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 100 }
		Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 200 }
	}

	It "asks the RPC preflight for its policy only with -Probe, and takes its attempt budget" {
		Mock Get-RpcRetryPolicy { @{ MaxAttempts = 1; InitialDelayMs = 0 } }
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1

		Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } | Should -Be 3
		Should -Invoke Get-RpcRetryPolicy -Times 0

		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1
		{ Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Probe -Label 'a sweep' } | Should -Throw
		Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter { $Probe -and $OperationLabel -eq 'a sweep' }
	}

	It "runs the operation in the caller's scope so its variables resolve" {
		$target = 2
		Invoke-VirtualDesktopOperation -Operation { Switch-Desktop -Desktop $target } -Label 'switching'

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
	}
}
