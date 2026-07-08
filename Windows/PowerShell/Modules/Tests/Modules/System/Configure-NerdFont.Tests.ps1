#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-NerdFont.ps1"
}

Describe "Configure-NerdFont" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			NerdFonts       = @{ JetBrainsMono = @{ SearchPattern = "JetBrainsMono*"; FolderName = "JetBrainsMonoNerdFont" } }
			DefaultNerdFont = "JetBrainsMono"
		}

		Mock Test-AdminPrivileges { }
		Mock Resolve-Selection { "JetBrainsMono" }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when requested font is not configured" {
		{ Configure-NerdFont -FontName "MissingFont" } | Should -Not -Throw

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Write-LogError -Times 1
	}
}
