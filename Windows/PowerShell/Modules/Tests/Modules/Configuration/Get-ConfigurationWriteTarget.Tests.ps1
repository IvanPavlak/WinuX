#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\Get-ConfigurationWriteTarget.ps1"
}

Describe "Get-ConfigurationWriteTarget" {
	BeforeEach {
		Mock Write-LogError { }

		$psDir = Join-Path $TestDrive "PowerShell"
		if (Test-Path $psDir) { Remove-Item -Path $psDir -Recurse -Force }
		New-Item -ItemType Directory -Path $psDir -Force | Out-Null
		$script:BaseFile = Join-Path $psDir "Configuration.psd1"
		$script:LocalFile = Join-Path $psDir "Configuration.local.psd1"
		Set-Content -Path $script:BaseFile -Value @(
			'@{'
			'	BrowserGroups = @('
			'		@{ Google = @("https://www.google.com/") }'
			'		@{ Docs = @("https://example.com/docs") }'
			'	)'
			'	PathTemplates = @{'
			'		SymbolicLinks = @{'
			'			Git = @{ Path = "{User}\.gitconfig"; Target = "{RepoRoot}\Git\.gitconfig" }'
			'		}'
			'	}'
			'}'
		)
	}

	It "targets Configuration.local.psd1 beside the base by default" {
		Set-Content -Path $script:LocalFile -Value @('@{', '}')

		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile

		$target.Path | Should -Be $script:LocalFile
		$target.FileName | Should -Be "Configuration.local.psd1"
		$target.IsLocal | Should -BeTrue
		$target.Created | Should -BeFalse
	}

	It "starts a missing local file as an empty hashtable without writing it" {
		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile

		$target.Created | Should -BeTrue
		@($target.Lines) | Should -Be @('@{', '}')
		Test-Path $script:LocalFile | Should -BeFalse
	}

	It "copies a missing array section whole from the base" {
		# An array in the local file replaces the base array at load, so a local list holding only
		# the new entry would hide every base entry.
		Set-Content -Path $script:LocalFile -Value @('@{', '	Other = "x"', '}')

		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile -CopySection 'BrowserGroups'

		$target.CopiedSections | Should -Be @('BrowserGroups')
		$parsed = Invoke-Expression (@($target.Lines) -join "`n")
		$parsed.Other | Should -Be "x"
		@($parsed.BrowserGroups).Count | Should -Be 2
		Test-Path $script:LocalFile | Should -BeTrue
		(Get-Content -Path $script:LocalFile -Raw) | Should -Not -Match 'BrowserGroups'
	}

	It "leaves a section the local file already has alone" {
		Set-Content -Path $script:LocalFile -Value @('@{', '	BrowserGroups = @(', '		@{ Mine = @("https://example.org") }', '	)', '}')

		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile -CopySection 'BrowserGroups'

		@($target.CopiedSections).Count | Should -Be 0
		$parsed = Invoke-Expression (@($target.Lines) -join "`n")
		@($parsed.BrowserGroups).Count | Should -Be 1
	}

	It "adds an empty hashtable section inside the parent the local file has" {
		Set-Content -Path $script:LocalFile -Value @('@{', '	PathTemplates = @{', '		ObsidianDirectory = "{Dev}\Vault"', '	}', '}')

		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile -HashtableSection 'PathTemplates.SymbolicLinks'

		$parsed = Invoke-Expression (@($target.Lines) -join "`n")
		$parsed.PathTemplates.ObsidianDirectory | Should -Be "{Dev}\Vault"
		$parsed.PathTemplates.SymbolicLinks | Should -BeOfType [hashtable]
		# Hashtables deep-merge, so the base links are not copied.
		$parsed.PathTemplates.SymbolicLinks.Count | Should -Be 0
	}

	It "adds the parent and the child when the local file has neither" {
		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath $script:BaseFile -HashtableSection 'PathTemplates.SymbolicLinks'

		$parsed = Invoke-Expression (@($target.Lines) -join "`n")
		$parsed.PathTemplates.SymbolicLinks | Should -BeOfType [hashtable]
	}

	It "returns an explicit file untouched, with no section copied in" {
		$explicit = Join-Path $TestDrive "Explicit.psd1"
		Set-Content -Path $explicit -Value @('@{', '}')

		$target = Get-ConfigurationWriteTarget -ConfigurationFilePath $explicit -BaseConfigurationPath $script:BaseFile -CopySection 'BrowserGroups'

		$target.Path | Should -Be $explicit
		$target.IsLocal | Should -BeFalse
		@($target.Lines) | Should -Be @('@{', '}')
	}

	It "targets the base file with -Base" {
		$target = Get-ConfigurationWriteTarget -Base -BaseConfigurationPath $script:BaseFile -CopySection 'BrowserGroups'

		$target.Path | Should -Be $script:BaseFile
		@($target.CopiedSections).Count | Should -Be 0
	}

	It "returns null and logs when the base file does not exist" {
		$target = Get-ConfigurationWriteTarget -BaseConfigurationPath (Join-Path $TestDrive "Missing.psd1")

		$target | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -Times 1 -Exactly
	}
}
