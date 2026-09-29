#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Get-ChassisType.ps1")

	# Stub the CIM cmdlet so Mock can attach to it on runners where the module is absent.
	if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
		function Get-CimInstance { param($ClassName, $ErrorAction) }
	}
}

Describe "Get-ChassisType" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @([uint16]10) } }
		# $TestDrive persists across the tests of a Describe, so each test gets its own cache folder.
		$script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + "\ChassisTypes.txt")
	}

	It "queries the hardware on the first call and writes the cache" {
		$result = Get-ChassisType -CachePath $script:cache

		$result | Should -Be @(10)
		Should -Invoke Get-CimInstance -Times 1
		Get-Content $script:cache | Should -Be @("10")
	}

	It "answers from the cache and leaves the hardware alone on the next call" {
		$null = Get-ChassisType -CachePath $script:cache
		$result = Get-ChassisType -CachePath $script:cache

		$result | Should -Be @(10)
		Should -Invoke Get-CimInstance -Times 1
	}

	It "queries the hardware again with -Refresh and rewrites the cache" {
		$null = Get-ChassisType -CachePath $script:cache
		Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @([uint16]3) } }

		$result = Get-ChassisType -Refresh -CachePath $script:cache

		$result | Should -Be @(3)
		Get-Content $script:cache | Should -Be @("3")
	}

	It "keeps every code of a multi-type chassis, in order" {
		Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @([uint16]9, [uint16]10) } }

		Get-ChassisType -CachePath $script:cache | Should -Be @(9, 10)
		Get-Content $script:cache | Should -Be @("9", "10")
	}

	It "ignores a cache that does not hold integers and re-creates it" {
		New-Item -ItemType Directory -Path (Split-Path $script:cache) -Force | Out-Null
		Set-Content -Path $script:cache -Value "laptop"

		Get-ChassisType -CachePath $script:cache | Should -Be @(10)
		Should -Invoke Get-CimInstance -Times 1
		Get-Content $script:cache | Should -Be @("10")
	}

	It "ignores an empty cache" {
		New-Item -ItemType Directory -Path (Split-Path $script:cache) -Force | Out-Null
		Set-Content -Path $script:cache -Value ""

		Get-ChassisType -CachePath $script:cache | Should -Be @(10)
		Should -Invoke Get-CimInstance -Times 1
	}

	It "returns the hardware answer even when the cache cannot be written" {
		Mock New-Item { throw "access denied" }

		{ $script:result = Get-ChassisType -CachePath $script:cache } | Should -Not -Throw
		$script:result | Should -Be @(10)
	}

	It "returns an empty list and writes no cache when the hardware reports nothing" {
		Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @() } }

		$result = @(Get-ChassisType -CachePath $script:cache)

		$result.Count | Should -Be 0
		Test-Path $script:cache | Should -BeFalse
	}
}
