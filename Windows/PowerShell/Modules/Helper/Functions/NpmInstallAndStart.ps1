function NpmInstallAndStart {
	<#
	.SYNOPSIS
		Install npm dependencies and start Node.js project.

	.DESCRIPTION
		Runs `npm install` followed by `npm start` in sequence.
		Useful for Node.js web app development workflows.

	.EXAMPLE
		NpmInstallAndStart
	#>
	npm install; npm start
}
