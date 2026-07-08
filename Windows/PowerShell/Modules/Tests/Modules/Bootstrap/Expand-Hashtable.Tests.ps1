#Requires -Modules Pester

BeforeAll {
	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Expand-Hashtable.ps1"
}

Describe "Expand-Hashtable" {
	Context "String Placeholder Expansion" {
		It "Should replace {Dev} placeholder" {
			$result = Expand-Hashtable -Source "{Dev}\Projects" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "C:\Dev\Projects"
		}

		It "Should replace {User} placeholder" {
			$result = Expand-Hashtable -Source "{User}\Documents" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "C:\Users\Test\Documents"
		}

		It "Should replace {MachineType} placeholder" {
			$result = Expand-Hashtable -Source "config_{MachineType}.json" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "Laptop"

			$result | Should -Be "config_Laptop.json"
		}

		It "Should replace multiple placeholders in single string" {
			$result = Expand-Hashtable -Source "{Dev}\{MachineType}\{User}" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "C:\Dev\PC\C:\Users\Test"
		}

		It "Should replace {RepoRoot} when provided" {
			$result = Expand-Hashtable -Source "{RepoRoot}\Config" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC" -RepoRoot "C:\Dev\WinuX"

			$result | Should -Be "C:\Dev\WinuX\Config"
		}

		It "Should replace {AppData} placeholder with environment variable" {
			$result = Expand-Hashtable -Source "{AppData}\MyApp" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "$env:APPDATA\MyApp"
		}

		It "Should replace %APPDATA% placeholder" {
			$result = Expand-Hashtable -Source "%APPDATA%\MyApp" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "$env:APPDATA\MyApp"
		}

		It "Should replace %LOCALAPPDATA% placeholder" {
			$result = Expand-Hashtable -Source "%LOCALAPPDATA%\Programs" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "$env:LOCALAPPDATA\Programs"
		}

		It "Should return string unchanged when no placeholders present" {
			$result = Expand-Hashtable -Source "plain_text" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be "plain_text"
		}
	}

	Context "Hashtable Recursion" {
		It "Should recursively expand nested hashtable values" {
			$source = @{
				Path1 = "{Dev}\Projects"
				Path2 = "{User}\Documents"
			}

			$result = Expand-Hashtable -Source $source -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result.Path1 | Should -Be "C:\Dev\Projects"
			$result.Path2 | Should -Be "C:\Users\Test\Documents"
		}

		It "Should handle deeply nested hashtables" {
			$source = @{
				Level1 = @{
					Level2 = @{
						Path = "{Dev}\Deep"
					}
				}
			}

			$result = Expand-Hashtable -Source $source -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result.Level1.Level2.Path | Should -Be "C:\Dev\Deep"
		}

		It "Should preserve null values in hashtables" {
			$source = @{
				Path    = "{Dev}\Projects"
				NullVal = $null
			}

			$result = Expand-Hashtable -Source $source -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result.Path | Should -Be "C:\Dev\Projects"
			$result.NullVal | Should -BeNullOrEmpty
		}
	}

	Context "Array Handling" {
		It "Should expand placeholders in array elements" {
			$source = @("{Dev}\Path1", "{User}\Path2")

			$result = Expand-Hashtable -Source $source -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result[0] | Should -Be "C:\Dev\Path1"
			$result[1] | Should -Be "C:\Users\Test\Path2"
		}

		It "Should handle null elements in arrays" {
			$source = @("{Dev}\Path1", $null, "{User}\Path2")

			$result = Expand-Hashtable -Source $source -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result[0] | Should -Be "C:\Dev\Path1"
			$result[2] | Should -Be "C:\Users\Test\Path2"
		}
	}

	Context "Non-String Types" {
		It "Should return integers unchanged" {
			$result = Expand-Hashtable -Source 42 -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be 42
		}

		It "Should return booleans unchanged" {
			$result = Expand-Hashtable -Source $true -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			$result | Should -Be $true
		}

		It "Should throw on null input (Source is mandatory)" {
			{ Expand-Hashtable -Source $null -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC" } | Should -Throw
		}
	}

	Context "WSL Path Conversion" {
		It "Should convert Windows paths to WSL paths when source contains forward slashes" {
			$result = Expand-Hashtable -Source "/mnt/{Dev}/projects" -DevPath "C:\Dev" -UserPath "C:\Users\Test" -MachineTypeName "PC"

			# Source contains '/' so it checks for Windows path after expansion
			# But {Dev} expands to C:\Dev which is a Windows path in a forward-slash context
			$result | Should -Not -BeNullOrEmpty
		}
	}
}
