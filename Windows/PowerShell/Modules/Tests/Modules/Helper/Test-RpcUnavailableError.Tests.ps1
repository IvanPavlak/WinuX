#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$HelperFunctionsPath\Test-RpcUnavailableError.ps1"

	function New-TestErrorRecord {
		param([Exception]$Exception)
		[System.Management.Automation.ErrorRecord]::new($Exception, "TestError", [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
	}
}

Describe "Test-RpcUnavailableError" {
	Context "Message strings" {
		It "classifies the classic 0x800706BA failure text" {
			Test-RpcUnavailableError 'Exception calling "Create" with "0" argument(s): "The RPC server is unavailable. (0x800706BA)"' | Should -BeTrue
		}

		It "classifies 0x80010108 (object disconnected from its clients)" {
			Test-RpcUnavailableError 'The object invoked has disconnected from its clients. (0x80010108)' | Should -BeTrue
		}

		It "classifies 0x800706BE (remote procedure call failed)" {
			Test-RpcUnavailableError 'The remote procedure call failed. (0x800706BE)' | Should -BeTrue
		}

		It "does not classify unrelated text" {
			Test-RpcUnavailableError 'The term ''Get-DesktopList'' is not recognized as a name of a cmdlet' | Should -BeFalse
		}
	}

	Context "Exceptions and error records" {
		It "classifies a COMException by HRESULT even when the message text is localized" {
			$comException = [System.Runtime.InteropServices.COMException]::new("Der RPC-Server ist nicht verfuegbar", [int]0x800706BA)

			Test-RpcUnavailableError $comException | Should -BeTrue
		}

		It "walks the InnerException chain of wrapper exceptions" {
			$comException = [System.Runtime.InteropServices.COMException]::new("rpc gone", [int]0x800706BA)
			$wrapped = [System.Reflection.TargetInvocationException]::new("Exception has been thrown by the target of an invocation.", $comException)

			Test-RpcUnavailableError $wrapped | Should -BeTrue
		}

		It "classifies a TypeInitializationException wrapping an RPC failure" {
			# The state a VirtualDesktop import leaves behind when its static
			# constructor ran while the shell endpoint was down.
			$comException = [System.Runtime.InteropServices.COMException]::new("rpc gone", [int]0x800706BA)
			$typeInit = [System.TypeInitializationException]::new("VirtualDesktop.DesktopManager", $comException)

			Test-RpcUnavailableError (New-TestErrorRecord -Exception $typeInit) | Should -BeTrue
		}

		It "classifies an ErrorRecord whose exception carries the RPC message" {
			$errorRecord = New-TestErrorRecord -Exception ([System.Exception]::new("The RPC server is unavailable. (0x800706BA)"))

			Test-RpcUnavailableError $errorRecord | Should -BeTrue
		}

		It "does not classify an unrelated exception" {
			Test-RpcUnavailableError ([System.InvalidOperationException]::new("file not found")) | Should -BeFalse
		}

		It "does not classify an unrelated ErrorRecord" {
			Test-RpcUnavailableError (New-TestErrorRecord -Exception ([System.IO.FileNotFoundException]::new("missing"))) | Should -BeFalse
		}
	}

	Context "Edge inputs" {
		It "returns false for null" {
			Test-RpcUnavailableError $null | Should -BeFalse
		}

		It "returns false for an empty string" {
			Test-RpcUnavailableError '' | Should -BeFalse
		}
	}
}
