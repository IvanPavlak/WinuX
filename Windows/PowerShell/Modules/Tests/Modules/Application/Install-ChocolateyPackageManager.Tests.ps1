#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-ChocolateyPackageManager.ps1"
}

Describe "Install-ChocolateyPackageManager" {
	BeforeEach {
		Mock Write-Host { }
		Mock Invoke-Expression { }
	}

	It "skips installation when choco command already exists" {
		Mock Get-Command { @{ Name = 'choco' } }

		Install-ChocolateyPackageManager

		Should -Invoke Invoke-Expression -Times 0
	}

	It "invokes installer expression when choco command is missing" {
		Mock Get-Command { $null }
		Mock New-Object {
			$wc = [PSCustomObject]@{}
			$wc | Add-Member -MemberType ScriptMethod -Name DownloadString -Value { param($u) 'Write-Output "install"' }
			return $wc
		}

		Install-ChocolateyPackageManager

		Should -Invoke Invoke-Expression -Times 1 -Exactly
	}
}
