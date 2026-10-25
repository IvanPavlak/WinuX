#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\List-AiArtifacts.ps1"
	. "$FunctionsPath\List-Skills.ps1"
}

# Deprecated since 1.6.0: a wrapper that warns once per session and forwards to
# List-AiArtifacts -Kind Skills, -Skill becoming -Name.
Describe "List-Skills" {
	BeforeEach {
		$script:AiDeprecationWarnings = $null
		Mock Write-LogWarning { }
		Mock List-AiArtifacts { }
	}

	It "lists the skills kind when called without filters" {
		List-Skills

		Should -Invoke List-AiArtifacts -Times 1 -Exactly -ParameterFilter { (@($Kind) -join ',') -eq 'Skills' -and -not $Source -and -not $Name -and -not $ListDiscrepancies }
	}

	It "forwards -Source as -Source" {
		List-Skills -Source own

		Should -Invoke List-AiArtifacts -Times 1 -Exactly -ParameterFilter { (@($Source) -join ',') -eq 'own' -and (@($Kind) -join ',') -eq 'Skills' }
	}

	It "forwards -Skill as -Name" {
		List-Skills -Skill alpha, bravo

		Should -Invoke List-AiArtifacts -Times 1 -Exactly -ParameterFilter { (@($Name) -join ',') -eq 'alpha,bravo' }
	}

	It "forwards -ListDiscrepancies and -Quiet" {
		List-Skills -ListDiscrepancies -Quiet

		Should -Invoke List-AiArtifacts -Times 1 -Exactly -ParameterFilter { $ListDiscrepancies -and $Quiet -and (@($Kind) -join ',') -eq 'Skills' }
	}

	It "warns once per session however often it is called" {
		List-Skills
		List-Skills -Source own

		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke List-AiArtifacts -Times 2 -Exactly
	}
}
