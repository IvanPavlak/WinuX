#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-GoogleTranslate.ps1"
}

Describe "Invoke-GoogleTranslate" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			DefaultTranslateLanguages = [PSCustomObject]@{
				OutputLanguage = "English"
			}
		}
		Mock Write-Warning { }
		Mock Write-Error { }
	}

	It "warns and returns when no translation text is provided" {
		{ Invoke-GoogleTranslate } | Should -Not -Throw
		Should -Invoke Write-Warning -Times 1
	}

	It "writes an error for unsupported output language" {
		{ Invoke-GoogleTranslate -Text "hello" -OutputLanguage "Klingon" } | Should -Not -Throw
		Should -Invoke Write-Error -Times 1
	}
}
