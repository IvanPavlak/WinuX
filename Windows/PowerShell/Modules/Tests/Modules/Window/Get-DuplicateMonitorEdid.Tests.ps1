#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-DuplicateMonitorEdid.ps1"
}

Describe "Get-DuplicateMonitorEdid" {
	It "returns the shared EDID when two displays report the same code" {
		$map = @{ '\\.\DISPLAY1' = 'AOCB316'; '\\.\DISPLAY2' = 'AOCB316' }

		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $map)

		$result.Count | Should -Be 1
		$result[0] | Should -Be 'AOCB316'
	}

	It "returns empty when every display has a distinct EDID" {
		$map = @{ '\\.\DISPLAY1' = 'AOCB316'; '\\.\DISPLAY2' = 'LEN8ABC' }

		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $map)

		$result.Count | Should -Be 0
	}

	It "reports each duplicated EDID once when three displays share two models" {
		$map = @{
			'\\.\DISPLAY1' = 'AOCB316'
			'\\.\DISPLAY2' = 'AOCB316'
			'\\.\DISPLAY3' = 'AOCB316'
		}

		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $map)

		$result.Count | Should -Be 1
		$result[0] | Should -Be 'AOCB316'
	}

	It "returns empty for a single-display map" {
		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap @{ '\\.\DISPLAY1' = 'AOCB316' })

		$result.Count | Should -Be 0
	}

	It "returns empty for a null map" {
		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $null)

		$result.Count | Should -Be 0
	}

	It "ignores blank EDID values when detecting duplicates" {
		$map = @{ '\\.\DISPLAY1' = ''; '\\.\DISPLAY2' = '' }

		$result = @(Get-DuplicateMonitorEdid -DisplayToEdidMap $map)

		$result.Count | Should -Be 0
	}
}
