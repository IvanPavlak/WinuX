#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Deploy-AiArtifacts.ps1"
	. "$FunctionsPath\Deploy-CoreAiRules.ps1"
}

# Deprecated since 1.6.0: a wrapper that warns once per session and forwards to Deploy-AiArtifacts,
# whose rules destinations include the WSL managed-settings link this function used to make.
Describe "Deploy-CoreAiRules" {
	BeforeEach {
		$script:AiDeprecationWarnings = $null
		Mock Write-LogWarning { }
		Mock Deploy-AiArtifacts { }
		Mock wsl { $global:LASTEXITCODE = 0 }
	}

	It "deploys the rules kind through Deploy-AiArtifacts and calls wsl itself no more" {
		Deploy-CoreAiRules

		Should -Invoke Deploy-AiArtifacts -Times 1 -Exactly -ParameterFilter { @($Kind) -join ',' -eq 'Rules' }
		Should -Invoke wsl -Times 0
	}

	It "warns once per session however often it is called" {
		Deploy-CoreAiRules
		Deploy-CoreAiRules

		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke Deploy-AiArtifacts -Times 2 -Exactly
	}
}
