#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Update-AiArtifacts.ps1"
	. "$FunctionsPath\Update-AiSkills.ps1"
}

# Deprecated since 1.6.0: a wrapper that warns once per session and forwards to Update-AiArtifacts.
Describe "Update-AiSkills" {
	BeforeEach {
		$script:AiDeprecationWarnings = $null
		Mock Write-LogWarning { }
		Mock Update-AiArtifacts { }
	}

	It "forwards to Update-AiArtifacts without a source filter when none is given" {
		Update-AiSkills

		Should -Invoke Update-AiArtifacts -Times 1 -Exactly -ParameterFilter { -not $Source -and -not $Check }
	}

	It "forwards -Source and -Check" {
		Update-AiSkills -Source mattpocock, other -Check

		Should -Invoke Update-AiArtifacts -Times 1 -Exactly -ParameterFilter { (@($Source) -join ',') -eq 'mattpocock,other' -and $Check }
	}

	It "warns once per session however often it is called" {
		Update-AiSkills
		Update-AiSkills -Check

		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke Update-AiArtifacts -Times 2 -Exactly
	}
}
