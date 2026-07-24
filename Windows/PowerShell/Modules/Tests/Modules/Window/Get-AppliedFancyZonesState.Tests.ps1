#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-AppliedFancyZonesState.ps1"

	$script:OriginalLocalAppData = $env:LOCALAPPDATA
}

AfterAll {
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
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

	It "adds an instance-qualified key alongside the EDID key when the schema records monitor-instance" {
		$env:LOCALAPPDATA = $TestDrive
		$zonesDir = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
		New-Item -Path $zonesDir -ItemType Directory -Force | Out-Null
		$jsonPath = Join-Path $zonesDir "applied-layouts.json"
		@'
{
  "applied-layouts": [
    {
      "device": {
        "monitor": "snybef3",
        "monitor-instance": "4&1cfdc60e&0&UID4145",
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

		# Legacy EDID-only key stays (instance-less callers / old schemas)...
		$result["SNYBEF3:{ABC-123}"] | Should -Be "{LAYOUT-1}"
		# ...and the instance-qualified key disambiguates duplicate-EDID monitors.
		$result["SNYBEF3|4&1CFDC60E&0&UID4145:{ABC-123}"] | Should -Be "{LAYOUT-1}"
	}
}
