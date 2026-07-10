@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Fork-owned Custom area loader - aggregates fork-local functions kept under Modules/Custom. See docs/contributing/fork-model.md (the Custom area)."
	RootModule        = "Custom.psm1"
	# The Custom area is fork-owned: upstream cannot know fork function names ahead of time, so
	# this manifest intentionally exports with a wildcard and the profile imports this module
	# eagerly at startup (autoload discovery is never relied upon for Custom functions). Engine
	# modules keep explicit FunctionsToExport lists - do not copy this pattern into them.
	FunctionsToExport = '*'
}
