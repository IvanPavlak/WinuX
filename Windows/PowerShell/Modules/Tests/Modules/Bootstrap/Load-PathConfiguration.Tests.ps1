#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Bootstrap\Functions"

	. "$FunctionsPath\Load-PathConfiguration.ps1"
	. "$FunctionsPath\Merge-Hashtable.ps1"

	# Stub dependent functions
	function Expand-Hashtable { param($Source, $DevPath, $UserPath, $MachineTypeName, $RepoRoot) $Source }
	function Expand-ConfigPaths { param($Configuration, $MachineType, $RepoRoot) @{} }
}

Describe "Load-PathConfiguration" {
	BeforeAll {
		$TestRepoRoot = Join-Path $TestDrive "WinuX"
		$ConfigDir = Join-Path $TestRepoRoot "Windows\PowerShell"
		New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

		# Create a minimal Configuration.psd1
		$configContent = @'
@{
    ValidMachineTypes = @("PC", "Laptop", "Work", "Test")
    DefaultMachineType = "Test"
    HostnameToMachineType = @{
        "MY-PC" = "PC"
    }
    BasePaths = @{
        Test = @{
            Dev = "C:\Dev"
            User = "C:\Users\Test"
        }
    }
    Universal = @{
        Desktop = ""
    }
}
'@
		Set-Content -Path (Join-Path $ConfigDir "Configuration.psd1") -Value $configContent
	}

	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Import-Module { }
		Mock Get-ChildItem { @() } -ParameterFilter { $Path -match "Modules$" }
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name MachineType -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name MachineSpecificPaths -Scope Global -ErrorAction SilentlyContinue
	}

	Context "When config file exists" {
		It "Should return true on successful load" {
			$result = Load-PathConfiguration -RepoRoot $TestRepoRoot

			$result | Should -BeTrue
		}

		It "Should set global Configuration variable" {
			Load-PathConfiguration -RepoRoot $TestRepoRoot

			$global:Configuration | Should -Not -BeNullOrEmpty
			$global:Configuration.ValidMachineTypes | Should -Contain "PC"
		}

		It "Should set MachineType from hostname mapping or default" {
			Load-PathConfiguration -RepoRoot $TestRepoRoot

			$global:MachineType | Should -Not -BeNullOrEmpty
		}
	}

	Context "When config file doesn't exist" {
		It "Should return false" {
			$result = Load-PathConfiguration -RepoRoot (Join-Path $TestDrive "NonExistent")

			$result | Should -BeFalse
		}
	}

	Context "When a local override exists" {
		It "Deep-merges Configuration.local.psd1 over the base config" {
			$localConfig = @'
@{
    DefaultMachineType    = "Machine"
    HostnameToMachineType = @{ "OVERRIDE-PC" = "Machine" }
}
'@
			Set-Content -Path (Join-Path $ConfigDir "Configuration.local.psd1") -Value $localConfig
			try {
				Load-PathConfiguration -RepoRoot $TestRepoRoot -Quiet | Out-Null
				$global:Configuration.DefaultMachineType                 | Should -Be "Machine"
				$global:Configuration.HostnameToMachineType["OVERRIDE-PC"] | Should -Be "Machine"
				# Deep merge keeps base keys, doesn't replace the whole hashtable.
				$global:Configuration.HostnameToMachineType["MY-PC"]     | Should -Be "PC"
			}
			finally {
				Remove-Item -Path (Join-Path $ConfigDir "Configuration.local.psd1") -ErrorAction SilentlyContinue
			}
		}
	}

	Context "When Quiet mode is used" {
		It "Should suppress output" {
			Load-PathConfiguration -RepoRoot $TestRepoRoot -Quiet

			# Should not invoke any visible logging for loading messages
			# (function logs only when -not $Quiet)
			Should -Invoke Write-LogTitle -Times 0
			Should -Invoke Write-LogSuccess -Times 0
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name MachineType -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name MachineSpecificPaths -Scope Global -ErrorAction SilentlyContinue
	}
}
