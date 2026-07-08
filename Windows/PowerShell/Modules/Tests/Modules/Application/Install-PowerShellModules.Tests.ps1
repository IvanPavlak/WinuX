#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-PowerShellModules.ps1"
}

Describe "Install-PowerShellModules" {
	BeforeEach {
		Mock Write-Host { }
		Mock Install-PackageProvider { }
		Mock Set-PSRepository { }
		Mock Install-Module { }

		Mock Get-PackageProvider { [PSCustomObject]@{ Name = 'NuGet' } }
		Mock Get-PSRepository { [PSCustomObject]@{ Name = 'PSGallery'; InstallationPolicy = 'Trusted' } }
		Mock Get-Module {
			param($ListAvailable, $Name)
			if ($Name -eq 'Pester') { return [PSCustomObject]@{ Version = [Version]'5.7.1' } }
			if ($Name -eq 'VirtualDesktop') { return [PSCustomObject]@{ Version = [Version]'1.5.11' } }
			return [PSCustomObject]@{ Version = [Version]'1.0.0' }
		}
	}

	It "does not install modules when required module versions are already present" {
		Install-PowerShellModules

		Should -Invoke Install-PackageProvider -Times 0
		Should -Invoke Set-PSRepository -Times 0
		Should -Invoke Install-Module -Times 0
	}
}
