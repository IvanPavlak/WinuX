#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Git\Functions\Resolve-UpstreamPathClass.ps1")

	$script:Winux = [pscustomobject]@{ Name = 'winux'; Own = @('Windows/', 'docs/winux/', 'PSScriptAnalyzerSettings.psd1'); Mirror = @('LICENSE', 'Git/.gitconfig') }
	$script:Foundation = [pscustomobject]@{ Name = 'foundation'; Own = @('Unix/', 'docs/foundation/'); Mirror = @('LICENSE', 'Git/.gitconfig') }
}

Describe "Resolve-UpstreamPathClass" {
	Context "the upstream's own rooms" {
		It "takes a path under an own folder" {
			Resolve-UpstreamPathClass -Path 'Windows/PowerShell/Modules/Git/Functions/GitPull.ps1' -Upstream $Winux -Others @($Foundation) -RootOwner 'fork' | Should -Be 'own'
		}

		It "takes an own file only by its exact path" {
			Resolve-UpstreamPathClass -Path 'PSScriptAnalyzerSettings.psd1' -Upstream $Winux -RootOwner 'fork' | Should -Be 'own'
			Resolve-UpstreamPathClass -Path 'PSScriptAnalyzerSettings.psd1.bak' -Upstream $Winux -RootOwner 'fork' | Should -Be 'declined'
		}

		It "does not treat a folder entry as a name prefix of a sibling" {
			Resolve-UpstreamPathClass -Path 'WindowsTerminal/settings.json' -Upstream $Winux -RootOwner 'fork' | Should -Be 'declined'
		}

		It "matches case-sensitively, as git paths are" {
			Resolve-UpstreamPathClass -Path 'windows/a.ps1' -Upstream $Winux -RootOwner 'fork' | Should -Be 'declined'
		}
	}

	Context "another upstream's rooms" {
		It "declines a path another upstream owns, even when this upstream owns the root" {
			Resolve-UpstreamPathClass -Path 'Unix/lib/foundation.sh' -Upstream $Winux -Others @($Foundation) -RootOwner 'winux' | Should -Be 'declined'
		}

		It "ignores the upstream's own manifest when it appears among the others" {
			Resolve-UpstreamPathClass -Path 'Windows/a.ps1' -Upstream $Winux -Others @($Winux, $Foundation) -RootOwner 'fork' | Should -Be 'own'
		}
	}

	Context "mirror files" {
		It "takes a mirror file from whichever upstream merges" {
			Resolve-UpstreamPathClass -Path 'LICENSE' -Upstream $Winux -Others @($Foundation) -RootOwner 'fork' | Should -Be 'mirror'
			Resolve-UpstreamPathClass -Path 'Git/.gitconfig' -Upstream $Foundation -Others @($Winux) -RootOwner 'fork' | Should -Be 'mirror'
		}
	}

	Context "the hallway" {
		It "declines a hallway path when the fork owns the root" {
			Resolve-UpstreamPathClass -Path 'README.md' -Upstream $Winux -Others @($Foundation) -RootOwner 'fork' | Should -Be 'declined'
		}

		It "declines a hallway path when another upstream owns the root" {
			Resolve-UpstreamPathClass -Path '.github/PULL_REQUEST_TEMPLATE.md' -Upstream $Winux -Others @($Foundation) -RootOwner 'foundation' | Should -Be 'declined'
		}

		It "takes a hallway path when the merged upstream owns the root" {
			Resolve-UpstreamPathClass -Path 'README.md' -Upstream $Winux -Others @($Foundation) -RootOwner 'winux' | Should -Be 'hallway'
		}

		It "adopts a hallway path through a take line of the fork's settings" {
			$settings = [pscustomobject]@{ Take = @([pscustomobject]@{ Upstream = 'winux'; Path = '.github/ISSUE_TEMPLATE/' }) }

			Resolve-UpstreamPathClass -Path '.github/ISSUE_TEMPLATE/bug_report.yml' -Upstream $Winux -Others @($Foundation) -Settings $settings -RootOwner 'fork' | Should -Be 'take'
		}

		It "ignores a take line that names another upstream" {
			$settings = [pscustomobject]@{ Take = @([pscustomobject]@{ Upstream = 'foundation'; Path = 'README.md' }) }

			Resolve-UpstreamPathClass -Path 'README.md' -Upstream $Winux -Others @($Foundation) -Settings $settings -RootOwner 'fork' | Should -Be 'declined'
		}
	}
}
