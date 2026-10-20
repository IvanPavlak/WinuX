#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$FunctionsPath\Install-VSCodeLocalExtensions.ps1"
	. "$FunctionsPath\Get-VSCodeLocalExtensions.ps1"
	. "$FunctionsPath\Resolve-VSCodeProfilesConfig.ps1"
}

Describe "Install-VSCodeLocalExtensions" {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
		Mock New-WindowsSymbolicLink { }
		Mock Remove-Item { }

		$script:Destination = Join-Path $TestDrive "extensions"
		$script:Source = Join-Path $TestDrive "repo\Extensions\Themes"
		$script:Extension = @{ Id = "publisher.themes"; Version = "1.1.0"; LinkName = "publisher.themes-1.1.0"; Source = $script:Source }

		# Symbolic links need elevation or Developer Mode, so the extensions folder is faked:
		# each test sets the links it holds.
		$script:Links = @()
		Mock Get-ChildItem { $script:Links } -ParameterFilter { $LiteralPath -eq $script:Destination }
		Mock Get-Item { $script:Links | Where-Object { $_.FullName -eq $LiteralPath } } -ParameterFilter { $LiteralPath -like "$script:Destination*" }
	}

	It "links an extension that is not linked yet under its <id>-<version> name" {
		Install-VSCodeLocalExtensions -Extension $script:Extension -Destination $script:Destination

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter {
			$Path -eq (Join-Path $script:Destination "publisher.themes-1.1.0") -and $Target -eq $script:Source
		}
	}

	It "leaves a link that already points at the extension's folder alone" {
		$script:Links = @([pscustomobject]@{
				Name     = "publisher.themes-1.1.0"
				FullName = Join-Path $script:Destination "publisher.themes-1.1.0"
				LinkType = "SymbolicLink"
				Target   = @($script:Source)
			})

		Install-VSCodeLocalExtensions -Extension $script:Extension -Destination $script:Destination

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Should -Invoke Remove-Item -Times 0
	}

	It "removes the link of an older version of the same extension, without -Recurse" {
		$old = Join-Path $script:Destination "publisher.themes-1.0.0"
		$script:Links = @([pscustomobject]@{ Name = "publisher.themes-1.0.0"; FullName = $old; LinkType = "SymbolicLink"; Target = @($script:Source) })

		Install-VSCodeLocalExtensions -Extension $script:Extension -Destination $script:Destination

		Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $old -and -not $Recurse }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly
	}

	It "never removes a real folder or a link that points somewhere else" {
		$script:Links = @(
			[pscustomobject]@{ Name = "publisher.themes-0.9.0"; FullName = Join-Path $script:Destination "publisher.themes-0.9.0"; LinkType = $null; Target = @() }
			[pscustomobject]@{ Name = "publisher.themes-1.0.0"; FullName = Join-Path $script:Destination "publisher.themes-1.0.0"; LinkType = "SymbolicLink"; Target = @("D:\Elsewhere\Themes") }
		)

		Install-VSCodeLocalExtensions -Extension $script:Extension -Destination $script:Destination

		Should -Invoke Remove-Item -Times 0
	}

	It "does nothing for an empty list" {
		Install-VSCodeLocalExtensions -Extension @() -Destination $script:Destination

		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "reads the extensions from VSCodeProfiles.Extensions when none are passed" {
		$root = Join-Path $TestDrive "repo\Extensions"
		Mock Resolve-VSCodeProfilesConfig { @{ Extensions = $root } }
		Mock Get-VSCodeLocalExtensions { $script:Extension } -ParameterFilter { $Root -eq $root }

		Install-VSCodeLocalExtensions -Destination $script:Destination

		Should -Invoke Get-VSCodeLocalExtensions -Times 1 -Exactly
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly
	}
}
