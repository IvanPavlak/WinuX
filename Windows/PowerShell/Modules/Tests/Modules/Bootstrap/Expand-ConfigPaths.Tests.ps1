#Requires -Modules Pester

BeforeAll {
	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Expand-Hashtable.ps1"
	. "$BootstrapFunctionsPath\Merge-Hashtable.ps1"
	. "$BootstrapFunctionsPath\Expand-ConfigPaths.ps1"
}

Describe "Expand-ConfigPaths" {
	Context "Basic Path Expansion" {
		It "Should expand path templates using base paths for the specified machine type" {
			$config = @{
				BasePaths        = @{
					PC = @{ Dev = "C:\Dev"; User = "C:\Users\You" }
				}
				PathTemplates    = @{
					Projects = @{
						Root = "{Dev}\Projects"
					}
				}
				MachineOverrides = @{}
			}

			$result = Expand-ConfigPaths -Configuration $config -MachineType "PC"

			$result.Projects.Root | Should -Be "C:\Dev\Projects"
		}

		It "Should apply machine overrides after template expansion" {
			$config = @{
				BasePaths        = @{
					Laptop = @{ Dev = "D:\Dev"; User = "C:\Users\You" }
				}
				PathTemplates    = @{
					Projects = @{
						Root    = "{Dev}\Projects"
						Special = "{Dev}\Special"
					}
				}
				MachineOverrides = @{
					Laptop = @{
						Projects = @{
							Special = "E:\OverriddenPath"
						}
					}
				}
			}

			$result = Expand-ConfigPaths -Configuration $config -MachineType "Laptop"

			$result.Projects.Root | Should -Be "D:\Dev\Projects"
			$result.Projects.Special | Should -Be "E:\OverriddenPath"
		}
	}

	Context "Fallback Behavior" {
		It "Should fall back to Test machine type when specified type is not in BasePaths" {
			$config = @{
				BasePaths        = @{
					Test = @{ Dev = "C:\TestDev"; User = "C:\Users\TestUser" }
				}
				PathTemplates    = @{
					Path1 = "{Dev}\Test"
				}
				MachineOverrides = @{}
			}

			$result = Expand-ConfigPaths -Configuration $config -MachineType "NonExistentType"

			$result.Path1 | Should -Be "C:\TestDev\Test"
		}
	}

	Context "Empty Overrides" {
		It "Should handle empty machine overrides gracefully" {
			$config = @{
				BasePaths        = @{
					PC = @{ Dev = "C:\Dev"; User = "C:\Users\Test" }
				}
				PathTemplates    = @{
					Path1 = "{Dev}\Projects"
				}
				MachineOverrides = @{
					PC = @{}
				}
			}

			$result = Expand-ConfigPaths -Configuration $config -MachineType "PC"

			$result.Path1 | Should -Be "C:\Dev\Projects"
		}
	}
}
