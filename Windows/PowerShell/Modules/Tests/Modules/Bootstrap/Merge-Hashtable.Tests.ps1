#Requires -Modules Pester

BeforeAll {
	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Merge-Hashtable.ps1"
}

Describe "Merge-Hashtable" {
	Context "Basic Merging" {
		It "Should add new keys from overrides" {
			$target = @{ A = 1 }
			$overrides = @{ B = 2 }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be 1
			$target.B | Should -Be 2
		}

		It "Should overwrite existing keys with override values" {
			$target = @{ A = 1 }
			$overrides = @{ A = 99 }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be 99
		}

		It "Should handle multiple keys in overrides" {
			$target = @{ A = 1; B = 2 }
			$overrides = @{ B = 20; C = 30 }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be 1
			$target.B | Should -Be 20
			$target.C | Should -Be 30
		}
	}

	Context "Deep Merging" {
		It "Should recursively merge nested hashtables" {
			$target = @{
				Level1 = @{
					A = 1
					B = 2
				}
			}
			$overrides = @{
				Level1 = @{
					B = 20
					C = 30
				}
			}

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.Level1.A | Should -Be 1
			$target.Level1.B | Should -Be 20
			$target.Level1.C | Should -Be 30
		}

		It "Should deeply merge multiple levels" {
			$target = @{
				L1 = @{
					L2 = @{
						L3   = "original"
						Keep = "preserved"
					}
				}
			}
			$overrides = @{
				L1 = @{
					L2 = @{
						L3 = "overridden"
					}
				}
			}

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.L1.L2.L3 | Should -Be "overridden"
			$target.L1.L2.Keep | Should -Be "preserved"
		}
	}

	Context "Type Replacement" {
		It "Should replace hashtable with non-hashtable value" {
			$target = @{ A = @{ Nested = 1 } }
			$overrides = @{ A = "replaced" }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be "replaced"
		}

		It "Should replace non-hashtable with hashtable value" {
			$target = @{ A = "original" }
			$overrides = @{ A = @{ Nested = 1 } }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A.Nested | Should -Be 1
		}
	}

	Context "Edge Cases" {
		It "Should handle empty overrides without changing target" {
			$target = @{ A = 1; B = 2 }
			$overrides = @{}

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be 1
			$target.B | Should -Be 2
			$target.Count | Should -Be 2
		}

		It "Should handle empty target by adding all override keys" {
			$target = @{}
			$overrides = @{ A = 1; B = 2 }

			Merge-Hashtable -Target $target -Overrides $overrides

			$target.A | Should -Be 1
			$target.B | Should -Be 2
		}
	}
}
