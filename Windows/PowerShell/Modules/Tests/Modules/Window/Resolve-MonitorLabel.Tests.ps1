#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-MonitorLabel.ps1"
}

Describe "Resolve-MonitorLabel" {
	Context "ordinal to label" {
		It "maps ordinal 0 to Primary" {
			Resolve-MonitorLabel -Index 0 | Should -Be 'Primary'
		}

		It "maps ordinal 1 to Secondary" {
			Resolve-MonitorLabel -Index 1 | Should -Be 'Secondary'
		}

		It "maps ordinals past Secondary to MonitorN with N one greater than the ordinal" {
			Resolve-MonitorLabel -Index 2 | Should -Be 'Monitor3'
			Resolve-MonitorLabel -Index 3 | Should -Be 'Monitor4'
			Resolve-MonitorLabel -Index 9 | Should -Be 'Monitor10'
		}

		It "accepts the ordinal positionally" {
			Resolve-MonitorLabel 2 | Should -Be 'Monitor3'
		}

		It "errors on a negative ordinal instead of inventing a label" {
			$result = Resolve-MonitorLabel -Index -1 -ErrorAction SilentlyContinue -ErrorVariable ordinalErrors

			$result | Should -BeNullOrEmpty
			@($ordinalErrors | Where-Object { $_.ToString() -match "0 or greater" }).Count | Should -BeGreaterThan 0
		}
	}

	Context "label to ordinal" {
		It "maps Primary and Secondary to ordinals 0 and 1" {
			Resolve-MonitorLabel -Label 'Primary' | Should -Be 0
			Resolve-MonitorLabel -Label 'Secondary' | Should -Be 1
		}

		It "maps MonitorN to ordinal N minus one" {
			Resolve-MonitorLabel -Label 'Monitor3' | Should -Be 2
			Resolve-MonitorLabel -Label 'Monitor4' | Should -Be 3
			Resolve-MonitorLabel -Label 'Monitor10' | Should -Be 9
		}

		It "gives Monitor3, Monitor4 and Monitor5 DISTINCT ordinals" {
			# The three-way Primary/Secondary/everything-else mapping this helper replaced
			# collapsed all of these to 2, so they tied and fell back to input order.
			$ordinals = @('Monitor3', 'Monitor4', 'Monitor5') | ForEach-Object { Resolve-MonitorLabel -Label $_ }

			@($ordinals | Select-Object -Unique).Count | Should -Be 3
		}

		It "treats Monitor1 and Monitor2 as the Primary and Secondary slots" {
			# Get-MonitorSpecs never emits these, but a hand-written layout file may use them.
			Resolve-MonitorLabel -Label 'Monitor1' | Should -Be 0
			Resolve-MonitorLabel -Label 'Monitor2' | Should -Be 1
		}

		It "matches labels case-insensitively and ignores surrounding whitespace" {
			Resolve-MonitorLabel -Label 'primary' | Should -Be 0
			Resolve-MonitorLabel -Label 'SECONDARY' | Should -Be 1
			Resolve-MonitorLabel -Label '  Monitor3  ' | Should -Be 2
		}

		It "sorts unrecognized labels last rather than tying them with real ones" {
			Resolve-MonitorLabel -Label 'Bogus' | Should -Be ([int]::MaxValue)
			Resolve-MonitorLabel -Label 'Monitor' | Should -Be ([int]::MaxValue)
			Resolve-MonitorLabel -Label 'Monitor0' | Should -Be ([int]::MaxValue)
			Resolve-MonitorLabel -Label 'Monitor3x' | Should -Be ([int]::MaxValue)
		}

		It "treats empty, whitespace and null labels as unrecognized" {
			Resolve-MonitorLabel -Label '' | Should -Be ([int]::MaxValue)
			Resolve-MonitorLabel -Label '   ' | Should -Be ([int]::MaxValue)
			Resolve-MonitorLabel -Label $null | Should -Be ([int]::MaxValue)
		}
	}

	Context "round trip and sorting" {
		It "round-trips every ordinal through its label" {
			foreach ($ordinal in 0..6) {
				Resolve-MonitorLabel -Label (Resolve-MonitorLabel -Index $ordinal) | Should -Be $ordinal
			}
		}

		It "orders a scrambled label set Primary, Secondary, Monitor3, Monitor4, ..." {
			$scrambled = @('Monitor5', 'Primary', 'Monitor3', 'Secondary', 'Monitor4')

			$sorted = @($scrambled | Sort-Object { Resolve-MonitorLabel -Label $_ })

			$sorted | Should -Be @('Primary', 'Secondary', 'Monitor3', 'Monitor4', 'Monitor5')
		}

		It "keeps unrecognized labels at the end of a sort" {
			$mixed = @('Monitor3', 'Bogus', 'Primary')

			$sorted = @($mixed | Sort-Object { Resolve-MonitorLabel -Label $_ })

			$sorted[-1] | Should -Be 'Bogus'
		}
	}
}
