#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Bootstrap\Functions"

	. "$FunctionsPath\Initialize-Configuration.ps1"

	# Stub logging so the function is self-contained in the test.
	function Write-LogError { param($Message) }
	function Write-LogSuccess { param($Message) }
	function Write-LogWarning { param($Message) }
}

Describe "Initialize-Configuration" {
	BeforeEach {
		# Any prompt is a bug. Tests supply GitName/GitEmail/DevPath; -Owner is intentionally
		# omitted in most cases to prove the function does NOT prompt for Owner when GitName is
		# already supplied (Owner only defaults GitName). This guards against the host-dependent
		# regression where the function prompted for Owner in an interactive console.
		Mock Read-Host { throw "Initialize-Configuration should not prompt when values are supplied" }
		$script:BaseConfig = Join-Path $TestDrive "Configuration.psd1"
		$script:LocalConfig = Join-Path $TestDrive "Configuration.local.psd1"
		Set-Content -Path $script:BaseConfig -Value "@{ GitConfig = @{ UserName = '' } }" -NoNewline
		Remove-Item -Path $script:LocalConfig -ErrorAction SilentlyContinue
	}

	It "writes the supplied Git identity and dev path into Configuration.local.psd1" {
		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-Owner "janedoe" -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -MachineType "Machine"

		Test-Path $script:LocalConfig | Should -BeTrue
		$result = Import-PowerShellDataFile -Path $script:LocalConfig
		$result.GitConfig.UserName    | Should -Be "Jane Doe"
		$result.GitConfig.UserEmail   | Should -Be "jane@example.com"
		$result.BasePaths.Machine.Dev | Should -Be "D:\Dev"
		$result.BasePaths.Machine.User | Should -Be $env:USERPROFILE
	}

	It "maps this machine's hostname to the given machine type" {
		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -MachineType "Machine"

		$result = Import-PowerShellDataFile -Path $script:LocalConfig
		$result.HostnameToMachineType[$env:COMPUTERNAME] | Should -Be "Machine"
	}

	It "does nothing when the override already has an identity and -Force is not given" {
		Set-Content -Path $script:LocalConfig -Value "@{ GitConfig = @{ UserName = 'Existing' } }" -NoNewline

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"

		$result = Import-PowerShellDataFile -Path $script:LocalConfig
		$result.GitConfig.UserName | Should -Be "Existing"
	}

	It "overwrites an existing override when -Force is given" {
		Set-Content -Path $script:LocalConfig -Value "@{ GitConfig = @{ UserName = 'Existing' } }" -NoNewline

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -Force

		$result = Import-PowerShellDataFile -Path $script:LocalConfig
		$result.GitConfig.UserName | Should -Be "Jane Doe"
	}

	It "writes a parseable override file" {
		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"

		{ Import-PowerShellDataFile -Path $script:LocalConfig } | Should -Not -Throw
	}

	It "defaults the override path beside Configuration.psd1, not inside Modules" {
		# Regression: with no -ConfigPath/-LocalConfigPath, the function must derive the override
		# path from $PSScriptRoot and land in <repo>\Windows\PowerShell (beside the base config that
		# Load-PathConfiguration reads), NOT one level deeper in ...\PowerShell\Modules. If it lands
		# in Modules the override is orphaned, never merged, and GitConfig stays blank on a fresh VM.
		# Mirror the real on-disk layout in TestDrive and dot-source a copy so its $PSScriptRoot
		# resolves there, then invoke WITHOUT explicit paths.
		$fnDir = Join-Path $TestDrive "Windows\PowerShell\Modules\Bootstrap\Functions"
		$psDir = Join-Path $TestDrive "Windows\PowerShell"
		New-Item -ItemType Directory -Path $fnDir -Force | Out-Null
		Set-Content -Path (Join-Path $psDir "Configuration.psd1") -Value "@{ GitConfig = @{ UserName = '' } }" -NoNewline
		Copy-Item "$FunctionsPath\Initialize-Configuration.ps1" (Join-Path $fnDir "Initialize-Configuration.ps1")

		. (Join-Path $fnDir "Initialize-Configuration.ps1")
		Initialize-Configuration -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -MachineType "Machine"

		Test-Path (Join-Path $psDir "Configuration.local.psd1")         | Should -BeTrue
		Test-Path (Join-Path $psDir "Modules\Configuration.local.psd1") | Should -BeFalse
	}
}
