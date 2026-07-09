#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force

	$script:PrevConfig = $global:Configuration
	$script:LogsDir = Join-Path $TestDrive 'Logs'
	$global:Configuration = @{
		Logging = @{
			DefaultLevel = 'Normal'
			Colors       = @{ Title = 'DarkCyan'; Step = 'White'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Debug = 'DarkCyan' }
			FileLogging  = @{
				Enabled       = $true
				Directory     = $script:LogsDir
				ErrorFileName = 'Errors.log'
				Retention     = @{ MaxAgeDays = 0; MaxSessionFiles = 0; MaxTotalSizeMB = 0; MaxErrorFileSizeMB = 0 }
			}
		}
	}
	Initialize-LoggingState -Force | Out-Null
}

AfterAll {
	$global:Configuration = $script:PrevConfig
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Write-Log engine" {
	BeforeEach {
		Initialize-LoggingState -Force | Out-Null
		Set-LogLevel Normal
	}

	Context "Structured file mirroring" {
		It "records every level in the session log at full detail" {
			Write-LogTitle "T"
			Write-LogStep "S"
			Write-LogSuccess "OK"
			Write-LogWarning "W"
			Write-LogError "E"

			$content = Get-Content (Get-LogPath) -Raw
			$content | Should -Match '\[TITLE\]'
			$content | Should -Match '\[STEP\]'
			$content | Should -Match '\[SUCCESS\]'
			$content | Should -Match '\[WARNING\]'
			$content | Should -Match '\[ERROR\]'
		}

		It "records suppressed debug lines in the file even though hidden on the console" {
			Set-LogLevel Normal
			Write-LogDebug "hidden-but-logged"
			(Get-Content (Get-LogPath) -Raw) | Should -Match 'hidden-but-logged'
		}

		It "writes the exception message and stack trace to the error log" {
			try { throw "boom-value" } catch { Write-LogError "operation failed" -Exception $_ }
			$err = Get-Content (Get-LogPath -ErrorLog) -Raw
			$err | Should -Match 'operation failed'
			$err | Should -Match 'boom-value'
			$err | Should -Match 'Exception =>'
		}

		It "tags each line with the originating caller, not the Write-Log wrapper" {
			function Test-CallerName { Write-LogStep "from-named-function" }
			Test-CallerName
			(Get-Content (Get-LogPath) -Raw) | Should -Match '\[Test-CallerName\]'
		}
	}

	Context "Console color mapping" {
		BeforeEach { Mock -ModuleName Logging Write-Host {} }

		It "uses <Color> for <Wrapper>" -ForEach @(
			@{ Wrapper = 'Write-LogSuccess'; Color = 'Green' }
			@{ Wrapper = 'Write-LogWarning'; Color = 'Yellow' }
			@{ Wrapper = 'Write-LogError'; Color = 'Red' }
			@{ Wrapper = 'Write-LogTitle'; Color = 'DarkCyan' }
			@{ Wrapper = 'Write-LogStep'; Color = 'White' }
		) {
			& $Wrapper "msg"
			Should -Invoke -ModuleName Logging Write-Host -ParameterFilter { $ForegroundColor -eq $Color }
		}

		It "renders a Step row in the -Style override color while keeping the plain Step layout and STEP file tag" {
			Write-LogStep " row => [disabled]" -Style Error
			# Red color, but the plain Step layout (no "=>" prefix added by the engine)
			Should -Invoke -ModuleName Logging Write-Host -ParameterFilter { $ForegroundColor -eq 'Red' -and $Object -eq "`n row => [disabled]" }
			(Get-Content (Get-LogPath) -Raw) | Should -Match '\[STEP\].*row => \[disabled\]'
		}
	}

	Context "Verbose gating" {
		It "does not print debug on the console at Normal level" {
			Mock -ModuleName Logging Write-Host {}
			Set-LogLevel Normal
			Write-LogDebug "x"
			Should -Invoke -ModuleName Logging Write-Host -Times 0 -Exactly
		}

		It "prints debug on the console at Verbose level" {
			Mock -ModuleName Logging Write-Host {}
			Set-LogLevel Verbose
			Write-LogDebug "x"
			Should -Invoke -ModuleName Logging Write-Host -Times 1 -Exactly
		}

		It "at Quiet level prints Error/Warning but not Step/Success" {
			Mock -ModuleName Logging Write-Host {}
			Set-LogLevel Quiet
			Write-LogStep "s"
			Write-LogSuccess "ok"
			Should -Invoke -ModuleName Logging Write-Host -Times 0 -Exactly
			Write-LogError "e"
			Write-LogWarning "w"
			Should -Invoke -ModuleName Logging Write-Host -Times 2 -Exactly
		}
	}

	Context "BlankLineAfter spacing" {
		BeforeEach {
			Mock -ModuleName Logging Write-Host {}
			Set-LogLevel Normal
		}

		It "appends a trailing newline to the console text with -BlankLineAfter" {
			Write-LogTitle "Header" -BlankLineAfter
			Should -Invoke -ModuleName Logging Write-Host -ParameterFilter { $Object -is [string] -and $Object.EndsWith("`n") }
		}

		It "does not append a trailing newline without -BlankLineAfter" {
			Write-LogTitle "Header"
			Should -Invoke -ModuleName Logging Write-Host -ParameterFilter { $Object -is [string] -and -not $Object.EndsWith("`n") }
		}
	}
}
