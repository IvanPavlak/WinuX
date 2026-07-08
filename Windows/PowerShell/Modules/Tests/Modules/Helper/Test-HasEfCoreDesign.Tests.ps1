#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Test-HasEfCoreDesign.ps1"
}

Describe "Test-HasEfCoreDesign" {
	Context "Project With EF Core Design Package" {
		It "Should return true when project contains Microsoft.EntityFrameworkCore.Design reference" {
			$testFile = Join-Path $TestDrive "test.csproj"
			@"
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="8.0.0" />
  </ItemGroup>
</Project>
"@ | Set-Content $testFile

			$result = Test-HasEfCoreDesign -projectPath $testFile

			$result | Should -Be $true
		}
	}

	Context "Project Without EF Core Design Package" {
		It "Should return false when project does not contain the design package" {
			$testFile = Join-Path $TestDrive "test_no_ef.csproj"
			@"
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
  </ItemGroup>
</Project>
"@ | Set-Content $testFile

			$result = Test-HasEfCoreDesign -projectPath $testFile

			$result | Should -Be $false
		}

		It "Should return false for empty project file" {
			$testFile = Join-Path $TestDrive "empty.csproj"
			"" | Set-Content $testFile

			$result = Test-HasEfCoreDesign -projectPath $testFile

			$result | Should -Be $false
		}
	}

	Context "Non-Existent Files" {
		It "Should return a falsy value for non-existent file" {
			$result = Test-HasEfCoreDesign -projectPath "C:\NonExistent\fake.csproj"

			[bool]$result | Should -Be $false
		}
	}
}
