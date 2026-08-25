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
		Remove-Item -Path "$($script:LocalConfig).bak" -ErrorAction SilentlyContinue
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

	It "leaves an existing override alone even when it carries no Git identity" {
		# Existence alone is the guard. The old "exists AND parses AND has an identity" check let
		# a fork's committed override - or any hand-edited file that had not filled in an identity
		# yet - be regenerated down to the three keys this writer knows, silently dropping the rest.
		$existing = "@{ BootstrapConfig = @{ Steps = @{ UpgradeAll = `$true } } }"
		Set-Content -Path $script:LocalConfig -Value $existing -NoNewline

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"

		Get-Content -Path $script:LocalConfig -Raw | Should -Be $existing
	}

	It "leaves an existing override alone even when it does not parse" {
		$existing = "@{ this is not valid powershell data"
		Set-Content -Path $script:LocalConfig -Value $existing -NoNewline

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"

		Get-Content -Path $script:LocalConfig -Raw | Should -Be $existing
	}

	It "overwrites an existing override when -Force is given, keeping a .bak copy" {
		Set-Content -Path $script:LocalConfig -Value "@{ GitConfig = @{ UserName = 'Existing' } }" -NoNewline

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -Force

		$result = Import-PowerShellDataFile -Path $script:LocalConfig
		$result.GitConfig.UserName | Should -Be "Jane Doe"

		$backup = Import-PowerShellDataFile -Path "$($script:LocalConfig).bak"
		$backup.GitConfig.UserName | Should -Be "Existing"
	}

	It "writes nothing when -Force cannot back the existing override up" {
		$existing = "@{ GitConfig = @{ UserName = 'Existing' } }"
		Set-Content -Path $script:LocalConfig -Value $existing -NoNewline
		Mock Copy-Item { throw "access denied" }

		Initialize-Configuration -ConfigPath $script:BaseConfig -LocalConfigPath $script:LocalConfig `
			-GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev" -Force

		Get-Content -Path $script:LocalConfig -Raw | Should -Be $existing
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
