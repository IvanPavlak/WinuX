#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Git\Functions\Resolve-UpstreamRemote.ps1")

	$script:Url = 'https://github.com/acme/MyUpstream.git'
}

Describe "Resolve-UpstreamRemote" {
	It "finds the remote by URL whatever it is called" {
		$resolved = Resolve-UpstreamRemote -Name 'winux' -Url $Url -Remotes @{ origin = 'https://github.com/you/MyRepo.git'; upstream = $Url }

		$resolved.Remote | Should -Be 'upstream'
		$resolved.Fix | Should -BeNullOrEmpty
	}

	It "compares URLs regardless of case, a user name, a trailing .git or slash, and the scp form" {
		foreach ($variant in 'https://you@GitHub.com/acme/myupstream', 'git@github.com:acme/MyUpstream.git', 'https://github.com/acme/MyUpstream/', 'ssh://git@github.com/acme/MyUpstream.git') {
			(Resolve-UpstreamRemote -Name 'winux' -Url $Url -Remotes @{ old = $variant }).Remote | Should -Be 'old' -Because "$variant is the same repository"
		}
	}

	It "prefers the remote named after the upstream when two remotes share the URL" {
		(Resolve-UpstreamRemote -Name 'winux' -Url $Url -Remotes @{ upstream = $Url; winux = $Url }).Remote | Should -Be 'winux'
	}

	It "says git remote set-url when the remote of that name points elsewhere" {
		$resolved = Resolve-UpstreamRemote -Name 'winux' -Url $Url -Remotes @{ winux = 'https://github.com/someone/Else.git' }

		$resolved.Remote | Should -BeNullOrEmpty
		$resolved.Fix | Should -Be "git remote set-url winux $Url"
	}

	It "says git remote add when no remote fits" {
		$resolved = Resolve-UpstreamRemote -Name 'foundation' -Url $Url -Remotes @{ origin = 'https://github.com/you/MyRepo.git' }

		$resolved.Remote | Should -BeNullOrEmpty
		$resolved.Fix | Should -Be "git remote add foundation $Url"
	}

	It "uses a remote of that name when there is no URL to compare" {
		(Resolve-UpstreamRemote -Name 'winux' -Url '' -Remotes @{ winux = $Url }).Remote | Should -Be 'winux'
	}

	It "has nothing to suggest without a URL or a remote of that name" {
		$resolved = Resolve-UpstreamRemote -Name 'winux' -Url $null -Remotes @{}

		$resolved.Remote | Should -BeNullOrEmpty
		$resolved.Fix | Should -BeNullOrEmpty
	}
}
