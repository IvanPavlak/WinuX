#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\ProcessGroupRecursive.ps1"
}

Describe "ProcessGroupRecursive" {
	Context "When processing NameUrl array structure" {
		It "Should add display items for group and each child" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Swagger") | Out-Null

			$groupValue = @(
				@{ Name = "API-1"; Url = "http://localhost:5000/swagger" },
				@{ Name = "API-2"; Url = "http://localhost:5001/swagger" }
			)

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$displayItems.Count | Should -Be 3  # Parent + 2 children
			$displayItems[0].Text | Should -Be "Swagger"
			$displayItems[1].Text | Should -Be "API-1"
			$displayItems[2].Text | Should -Be "API-2"
		}

		It "Should create lookup entries by index path and name" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Tools") | Out-Null

			$groupValue = @(
				@{ Name = "Swagger"; Url = "http://localhost/swagger" }
			)

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$lookupMap.ContainsKey("1") | Should -BeTrue
			$lookupMap.ContainsKey("Tools") | Should -BeTrue
			$lookupMap.ContainsKey("1.1") | Should -BeTrue
			$lookupMap.ContainsKey("Swagger") | Should -BeTrue
		}
	}

	Context "When processing nested hashtable structure" {
		It "Should recurse into nested groups" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Parent") | Out-Null

			$groupValue = @(
				@{
					"Child" = @(
						@{ Name = "Item1"; Url = "http://example.com" }
					)
				}
			)

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$displayItems.Count | Should -BeGreaterOrEqual 3  # Parent, Child, Item1
			$lookupMap.ContainsKey("1.1") | Should -BeTrue
			$lookupMap["1.1"].PathNames | Should -Contain "Child"
		}
	}

	Context "When processing string array structure" {
		It "Should add only the parent display item" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("StringGroup") | Out-Null

			$groupValue = @("item1", "item2", "item3")

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$displayItems.Count | Should -Be 1
			$lookupMap["1"].StructureType | Should -Be "StringArray"
		}
	}

	Context "When processing mixed array structure (NameUrl + nested hashtables)" {
		It "Should process both NameUrl items and nested sub-groups" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("DomainLinks") | Out-Null

			$groupValue = @(
				@{ Name = "Homepage"; Url = "https://homepage.example.com" },
				@{ Name = "Proxmox"; Url = "https://proxmox.example.com" },
				@{ ArrStack = @(
						@{ Name = "Radarr"; Url = "https://radarr.example.com" }
						@{ Name = "Sonarr"; Url = "https://sonarr.example.com" }
					)
				}
			)

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$lookupMap["1"].StructureType | Should -Be "MixedArray"

			# Parent + 2 NameUrl leaves + ArrStack sub-group + 2 ArrStack leaves = 6
			$displayItems.Count | Should -Be 6

			$lookupMap.ContainsKey("Homepage") | Should -BeTrue
			$lookupMap.ContainsKey("Proxmox") | Should -BeTrue
			$lookupMap.ContainsKey("ArrStack") | Should -BeTrue
			$lookupMap.ContainsKey("Radarr") | Should -BeTrue
			$lookupMap.ContainsKey("Sonarr") | Should -BeTrue

			$lookupMap["Homepage"].StructureType | Should -Be "Leaf"
			$lookupMap["ArrStack"].StructureType | Should -Be "NameUrlArray"
		}

		It "Should assign correct index paths for mixed items" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Links") | Out-Null

			$groupValue = @(
				@{ Name = "Item1"; Url = "http://item1.com" },
				@{ SubGroup = @(
						@{ Name = "SubItem1"; Url = "http://sub1.com" }
					)
				},
				@{ Name = "Item2"; Url = "http://item2.com" }
			)

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "2" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$lookupMap["2.1"].PathNames | Should -Contain "Item1"
			$lookupMap["2.2"].PathNames | Should -Contain "SubGroup"
			$lookupMap["2.3"].PathNames | Should -Contain "Item2"

			$lookupMap["2"].DirectChildren.Count | Should -Be 3
		}
	}

	Context "Lookup entry structure" {
		It "Should set correct StructureType for NameUrl arrays" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Group") | Out-Null

			$groupValue = @(@{ Name = "A"; Url = "http://a.com" })

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "1" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 0

			$lookupMap["1"].StructureType | Should -Be "NameUrlArray"
			$lookupMap["1"].DirectChildren.Count | Should -Be 1
		}

		It "Should track depth correctly for nested items" {
			$displayItems = [System.Collections.ArrayList]::new()
			$lookupMap = @{}
			$pathNames = [System.Collections.ArrayList]::new()
			$pathNames.Add("Root") | Out-Null

			$groupValue = @(@{ Name = "Leaf"; Url = "http://leaf.com" })

			ProcessGroupRecursive -GroupValue $groupValue -IndexPath "2" -DisplayItems $displayItems -LookupMap $lookupMap -PathNames $pathNames -Depth 3

			$displayItems[0].Depth | Should -Be 3
			$displayItems[1].Depth | Should -Be 4
		}
	}
}
