#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-PwshPath.ps1"

	$script:SavedLocalAppData = $env:LOCALAPPDATA
	$script:MsixHome = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.7.0.0_x64__8wekyb3d8bbwe'

	# Creates an empty file standing in for pwsh.exe or one of its aliases.
	function New-TestFile {
		param([Parameter(Mandatory)][string]$Path)
		New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
		New-Item -ItemType File -Path $Path -Force | Out-Null
		$Path
	}
}

AfterAll {
	$env:LOCALAPPDATA = $script:SavedLocalAppData
}

Describe "Get-PwshPath" {
	BeforeEach {
		$script:Root = Join-Path (Get-PSDrive -Name TestDrive).Root ([guid]::NewGuid().ToString('N'))
		$env:LOCALAPPDATA = Join-Path $script:Root 'LocalAppData'
		$script:AliasRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
	}

	Context "an install outside WindowsApps (MSI or zip)" {
		It "returns its own pwsh.exe, even when an MSIX alias exists too" {
			$installHome = Join-Path $script:Root 'PowerShell\7'
			$own = New-TestFile (Join-Path $installHome 'pwsh.exe')
			New-TestFile (Join-Path $script:AliasRoot 'Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe') | Out-Null

			Get-PwshPath -PowerShellHome $installHome | Should -Be $own
			Should -Invoke Get-Command -Times 0 -ParameterFilter { $Name -eq 'pwsh' }
		}

		It "falls back to the pwsh on PATH when its own pwsh.exe is missing" {
			$installHome = Join-Path $script:Root 'Gone'
			Mock Get-Command { [pscustomobject]@{ Source = 'D:\Tools\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }

			Get-PwshPath -PowerShellHome $installHome | Should -Be 'D:\Tools\pwsh.exe'
		}
	}

	Context "the MSIX package" {
		It "returns the version-free alias of its own package family, never the versioned package folder" {
			$familyAlias = New-TestFile (Join-Path $script:AliasRoot 'Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe')
			New-TestFile (Join-Path $script:AliasRoot 'pwsh.exe') | Out-Null

			$result = Get-PwshPath -PowerShellHome $script:MsixHome

			$result | Should -Be $familyAlias
			$result | Should -Not -BeLike '*7.7.0.0*'
		}

		It "takes the family alias of the package that runs, not another package's (LTS)" {
			$ltsAlias = New-TestFile (Join-Path $script:AliasRoot 'Microsoft.PowerShell.LTS_8wekyb3d8bbwe\pwsh.exe')
			New-TestFile (Join-Path $script:AliasRoot 'Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe') | Out-Null

			Get-PwshPath -PowerShellHome 'C:\Program Files\WindowsApps\Microsoft.PowerShell.LTS_7.6.10.0_x64__8wekyb3d8bbwe\' | Should -Be $ltsAlias
		}

		It "falls back to the shared alias when the family alias is missing" {
			$sharedAlias = New-TestFile (Join-Path $script:AliasRoot 'pwsh.exe')

			Get-PwshPath -PowerShellHome $script:MsixHome | Should -Be $sharedAlias
		}

		It "falls back to the pwsh on PATH when no alias exists" {
			Mock Get-Command { [pscustomobject]@{ Source = 'C:\Program Files\PowerShell\7\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }

			Get-PwshPath -PowerShellHome $script:MsixHome | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
		}
	}

	It "returns the pwsh.exe under -PowerShellHome as a last resort" {
		Get-PwshPath -PowerShellHome $script:MsixHome | Should -Be (Join-Path $script:MsixHome 'pwsh.exe')
	}

	It "resolves from the running shell's own folder by default" {
		Get-PwshPath | Should -Be (Get-PwshPath -PowerShellHome $PSHOME)
	}
}
