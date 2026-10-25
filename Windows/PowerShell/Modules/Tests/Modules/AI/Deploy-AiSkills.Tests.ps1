#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Deploy-AiArtifacts.ps1"
	. "$FunctionsPath\Deploy-AiSkills.ps1"
}

# Deprecated since 1.6.0: a wrapper that warns once per session and forwards to Deploy-AiArtifacts.
Describe "Deploy-AiSkills" {
	BeforeEach {
		$script:AiDeprecationWarnings = $null
		Mock Write-LogWarning { }
		Mock Deploy-AiArtifacts { }
	}

	It "deploys the skills kind through Deploy-AiArtifacts" {
		Deploy-AiSkills

		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { @($Kind) -join ',' -eq 'Skills' }
	}

	It "warns once per session however often it is called" {
		Deploy-AiSkills
		Deploy-AiSkills

		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke Deploy-AiArtifacts -Times 2 -Exactly
	}
}
