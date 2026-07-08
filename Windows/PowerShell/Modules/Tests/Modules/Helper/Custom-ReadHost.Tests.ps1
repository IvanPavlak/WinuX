#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Custom-ReadHost.ps1"
}

Describe "Custom-ReadHost" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "returns plain input when AsSecureString is not specified" {
		Mock Read-Host { "sample-input" }

		$result = Custom-ReadHost -PromptMessage "Enter value"

		$result | Should -Be "sample-input"
		Should -Invoke Read-Host -Times 1
		Should -Invoke Write-Host -Times 1
	}

	It "requests secure input when AsSecureString is specified" {
		# Build a SecureString without ConvertTo-SecureString -AsPlainText, which PSScriptAnalyzer
		# flags (PSAvoidUsingConvertToSecureStringWithPlainText). The test only needs a [securestring].
		$secure = [System.Security.SecureString]::new()
		'secret'.ToCharArray() | ForEach-Object { $secure.AppendChar($_) }
		Mock Read-Host { $secure } -ParameterFilter { $AsSecureString }

		$result = Custom-ReadHost -PromptMessage "Enter password" -AsSecureString

		$result | Should -BeOfType ([securestring])
		Should -Invoke Read-Host -Times 1 -ParameterFilter { $AsSecureString }
	}
}
