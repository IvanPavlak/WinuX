#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Update-AiArtifacts.ps1"
	. "$FunctionsPath\Update-AiMods.ps1"
}

# Deprecated since 1.6.0: a wrapper that warns once per session and forwards to Update-AiArtifacts.
Describe "Update-AiMods" {
	BeforeEach {
		$script:AiDeprecationWarnings = $null
		Mock Write-LogWarning { }
		Mock Update-AiArtifacts { }
	}

	It "forwards to Update-AiArtifacts without a source filter when none is given" {
		Update-AiMods

		Should -Invoke Update-AiArtifacts -Times 1 -Exactly -ParameterFilter { -not $Source -and -not $Check }
	}

	It "forwards -Source and -Check" {
		Update-AiMods -Source my-mod -Check

		Should -Invoke Update-AiArtifacts -Times 1 -Exactly -ParameterFilter { (@($Source) -join ',') -eq 'my-mod' -and $Check }
	}

	It "warns once per session however often it is called" {
		Update-AiMods
		Update-AiMods

		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke Update-AiArtifacts -Times 2 -Exactly
	}
}
