#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-AppliedFancyZonesState.ps1"
}

Describe "Get-AppliedFancyZonesState" {
	BeforeEach {
		$script:AppliedLayoutsCache = @{
			Data      = $null
			Timestamp = [datetime]::MinValue
			MaxAgeSec = 10
		}
	}

	It "returns null when applied-layouts file does not exist" {
		$env:LOCALAPPDATA = "C:\NoSuchPath"

		$result = Get-AppliedFancyZonesState

		$result | Should -Be $null
	}

	It "parses json and builds uppercase monitor-desktop lookup" {
		$env:LOCALAPPDATA = $TestDrive
		$zonesDir = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
		New-Item -Path $zonesDir -ItemType Directory -Force | Out-Null
		$jsonPath = Join-Path $zonesDir "applied-layouts.json"
		@'
{
  "applied-layouts": [
    {
      "device": {
        "monitor": "len8abc",
        "virtual-desktop": "{abc-123}"
      },
      "applied-layout": {
        "uuid": "{layout-1}"
      }
    }
  ]
}
'@ | Set-Content -Path $jsonPath

		$result = Get-AppliedFancyZonesState -Force

		$result["LEN8ABC:{ABC-123}"] | Should -Be "{LAYOUT-1}"
	}
}
