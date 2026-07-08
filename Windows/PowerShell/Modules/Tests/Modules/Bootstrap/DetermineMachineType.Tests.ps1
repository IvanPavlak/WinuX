#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Bootstrap\Functions"

	. "$FunctionsPath\DetermineMachineType.ps1"

	# Stub Custom-ReadHost to avoid interactive prompts
	function Custom-ReadHost { param($Prompt, [switch]$AddNewLine) "" }
}

Describe "DetermineMachineType" {
	BeforeAll {
		$global:Configuration = @{
			ValidMachineTypes     = @("PC", "Laptop", "Work", "Test")
			HostnameToMachineType = @{
				"DESKTOP-PC"   = "PC"
				"LAPTOP-HOME"  = "Laptop"
				"WORK-MACHINE" = "Work"
			}
		}
	}

	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		# Clear any pre-defined MachineType
		Remove-Variable -Name MachineType -Scope Global -ErrorAction SilentlyContinue
	}

	Context "When MachineType is already set globally" {
		It "Should return the existing valid MachineType" {
			$global:MachineType = "PC"

			$result = DetermineMachineType

			$result | Should -Be "PC"
		}

		It "Should reject an invalid pre-defined MachineType" {
			$global:MachineType = "InvalidType"
			# Mock hostname lookup to return a known type
			$originalHostname = $env:COMPUTERNAME
			$env:COMPUTERNAME = "DESKTOP-PC"

			$result = DetermineMachineType

			$result | Should -Be "PC"

			$env:COMPUTERNAME = $originalHostname
		}
	}

	Context "When hostname maps to a machine type" {
		It "Should return the mapped type for a known hostname" {
			$originalHostname = $env:COMPUTERNAME
			$env:COMPUTERNAME = "DESKTOP-PC"

			$result = DetermineMachineType

			$result | Should -Be "PC"
			$global:MachineType | Should -Be "PC"

			$env:COMPUTERNAME = $originalHostname
		}

		It "Should return Laptop for laptop hostname" {
			$originalHostname = $env:COMPUTERNAME
			$env:COMPUTERNAME = "LAPTOP-HOME"

			$result = DetermineMachineType

			$result | Should -Be "Laptop"

			$env:COMPUTERNAME = $originalHostname
		}
	}

	Context "When hostname is unknown" {
		It "Should prompt for machine type and accept valid input" {
			$originalHostname = $env:COMPUTERNAME
			$env:COMPUTERNAME = "UNKNOWN-MACHINE"
			Mock Custom-ReadHost { "Test" }

			$result = DetermineMachineType

			$result | Should -Be "Test"
			$global:MachineType | Should -Be "Test"

			$env:COMPUTERNAME = $originalHostname
		}
	}

	AfterAll {
		Remove-Variable -Name MachineType -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
