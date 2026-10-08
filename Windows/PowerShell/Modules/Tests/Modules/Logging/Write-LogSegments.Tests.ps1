#Requires -Modules Pester

BeforeAll {
	# Put back exactly the logging state and configuration this file found (see Write-Log.Tests.ps1).
	$script:SavedLoggingState = $global:LoggingState
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force

	$script:PrevConfig = $global:Configuration
	$global:Configuration = @{
		Logging = @{
			DefaultLevel = 'Normal'
			Colors       = @{ Title = 'DarkCyan'; Step = 'White'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Debug = 'DarkCyan'; Info = 'Blue' }
			FileLogging  = @{
				Enabled       = $true
				Directory     = (Join-Path $TestDrive 'Logs')
				ErrorFileName = 'Errors.log'
				Retention     = @{ MaxAgeDays = 0; MaxSessionFiles = 0; MaxTotalSizeMB = 0; MaxErrorFileSizeMB = 0 }
			}
		}
	}
	Initialize-LoggingState -Force | Out-Null
}

AfterAll {
	$global:Configuration = $script:PrevConfig
	$global:LoggingState = $script:SavedLoggingState
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Write-LogSegments" {
	BeforeEach {
		Initialize-LoggingState -Force | Out-Null
		Set-LogLevel Normal
		$script:Drawn = [System.Collections.Generic.List[object]]::new()
		Mock -ModuleName Logging Write-Host { $script:Drawn.Add([pscustomobject]@{ Text = $Object; Color = "$ForegroundColor"; NoNewline = [bool]$NoNewline }) }
	}

	It "draws each segment in its palette color on one line, with the leading newline before the first" {
		Write-LogSegments @(@{ Text = "=> Totals => " }, @{ Text = "2 updated"; Style = "Info" }, @{ Text = ", " }, @{ Text = "1 failed"; Style = "Error" })

		($script:Drawn | ForEach-Object { $_.Color }) -join "," | Should -Be "White,Blue,White,Red"
		$script:Drawn[0].Text | Should -Be "`n=> Totals => "
		($script:Drawn | ForEach-Object { $_.NoNewline }) -join "," | Should -Be "True,True,True,False"
	}

	It "draws a segment with an unknown style in the Step color" {
		Write-LogSegments @(@{ Text = "x"; Style = "Sparkly" })

		$script:Drawn[0].Color | Should -Be "White"
	}

	It "omits the leading newline with -NoLeadingNewline" {
		Write-LogSegments @(@{ Text = "x" }) -NoLeadingNewline

		$script:Drawn[0].Text | Should -Be "x"
	}

	It "writes the whole line to the session log once, as a STEP entry" {
		Write-LogSegments @(@{ Text = "seg-one " ; Style = "Success" }, @{ Text = "seg-two"; Style = "Error" })

		$lines = @(Get-Content (Get-LogPath) | Where-Object { $_ -match "seg-one" })
		$lines.Count | Should -Be 1
		$lines[0] | Should -Match '\[STEP\].*seg-one seg-two'
	}

	It "draws nothing at the Quiet level but still logs the line" {
		Set-LogLevel Quiet

		Write-LogSegments @(@{ Text = "quiet-line" })

		$script:Drawn.Count | Should -Be 0
		(Get-Content (Get-LogPath) -Raw) | Should -Match 'quiet-line'
	}

	It "does nothing for no segments" {
		Write-LogSegments @()

		$script:Drawn.Count | Should -Be 0
	}
}
