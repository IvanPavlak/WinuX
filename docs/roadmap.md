# Roadmap

WinuX is a stable project with a settled identity: a deeply configurable Windows 11
distribution for people who want their Windows machine to behave like their Linux box, and who
are willing to edit a configuration file to get there. The terminal and `Configuration.psd1` are
the product, not a stage on the way to something more approachable.

This page is a high-level view of where the project is and where it's headed. It is intentionally
direction-over-dates - priorities shift as contributors get involved. For shipped changes see the
[CHANGELOG](https://github.com/IvanPavlak/WinuX/blob/master/CHANGELOG.md); for how versions are
numbered, and what a MAJOR, MINOR or PATCH promises your fork, see
[VERSIONING](https://github.com/IvanPavlak/WinuX/blob/master/VERSIONING.md).

## Who WinuX is for

WinuX is **terminal- and keyboard-driven**, built for power users comfortable editing a PowerShell
configuration file. From a single `Configuration.psd1` (plus a personal `Configuration.local.psd1`
override) one command provisions a whole machine: system settings, software, dotfiles,
repositories, and window workspaces. It is tested across VMware and real machines, with a full
Pester suite, a man-style reference for every function, and a configuration guide for every
exported function.

If you have ever kept a dotfiles repository, written a window-manager config, or maintained a
package list for a Linux install, WinuX is the same habit applied to Windows. If you have not,
WinuX will ask more of you than a one-click tweaker does - and give you a machine that is yours
in return.

## Non-goals

These are deliberate. They keep the project honest about what it is.

- **No graphical front-end from the maintainer.** Tools like Chris Titus Tech's WinUtil and the
  Win11Debloat project already do the checkbox-driven job well. WinuX does not compete with them;
  it vendors Win11Debloat as an optional bootstrap step for exactly that reason. The current sole
  maintainer has no interest in building a GUI and will not plan one. That is a statement about
  the maintainer's time, not a veto: a contributor who wants to build a graphical front-end that
  reads and writes the *same* `Configuration.psd1` the CLI uses is welcome to, and the
  configurability principle below is the only condition.
- **No wizard for people who will not open a terminal.** The guided path that exists, the
  [WinuXConfigurator](configuration/winux-configurator.md) interview, writes the same
  configuration file you could write by hand. It helps you decide; it never hides the file.
- **No opinionated defaults, and no example profiles.** A vanilla install changes no theme,
  wallpaper, locale, keyboard layout, or taskbar. Every feature is opted into in your own override.
  Shipping WinuX empty is what lets you make it your own; a set of ready-made profiles would only
  be someone else's choices to undo.
- **No second configuration system.** Everything a function does is driven by `Configuration.psd1`
  and the data files beside it (the app-list CSVs and the window layout files), all documented in
  the configuration reference. There is no settings store outside them.

## Guiding principles

- **Configurability is never sacrificed.** Anything that makes a decision easier sits *on top of*
  the declarative config - it never replaces or hides it.
- **One source of truth.** The documentation and `Configuration.psd1` describe the whole system;
  no behavior is hidden.
- **Reproducible and idempotent.** Re-running anything is always safe.
- **No personal data in the project.** Your identity and paths live only in your local override,
  your `*.local.csv` overlays and the [Custom area](contributing/fork-model.md).
- **A fork can always merge.** Breaking changes are deprecated first and removed later, in a
  MAJOR release, so a fork that keeps its warnings at zero merges every release cleanly.

## Now - 1.0

- **The contract is declared stable.** The configuration schema, the bootstrap contract and the
  set of exported functions are versioned under strict semantic versioning from 1.0.0 onward,
  with the deprecation policy described in VERSIONING.
- **The personal-fork model is the supported way to use WinuX.** A maintainer's own machine and
  the public project share one source of truth; see the [Fork Model](contributing/fork-model.md)
  page.

## Next - the 1.x series

WinuX is the maintainer's daily system, and the 1.x releases carry what daily use produces:
fixes, new functions, new configuration options, and version pins that follow the tested
machines. There is no feature list to tick off. Three things are known to be ahead, and none
has a date:

- **Deprecation warnings where you will see them** - they arrive with the next deprecated
  configuration key, not before. `Test-ConfigurationSchema` will warn on the old key and name its
  replacement, at every profile load and at the start of the bootstrap, so you learn what to
  migrate before the next MAJOR removes it. The two keys deprecated during 0.x
  (`BootstrapConfig.WSLSetup`, still honored, and `PathTemplates.ObsidianStartupScript`, ignored)
  are covered by the same mechanism when it lands.
- **Multi-monitor arrangements beyond the maintainer's own** - tested when that hardware is at
  hand. Other hardware, display scaling, keyboard layouts and locales the maintainer does not run
  are covered by the people who run them: a bug report with a configuration that reproduces it is
  the way in.
- **A custom installation image per machine** - a Windows reinstall is rare, but when it happens
  it is the slowest part of getting a machine back: the installer, then the first boot, then the
  bootstrap. An ISO creator would build a Windows 11 image from a fork's configuration for one
  machine type - the unattended answers, the framework apps and the WinuX bootstrap already in it -
  so a reinstall goes from boot to a provisioned machine with as little waiting and typing as
  possible. The image is built and stored when it is needed, not shipped: it carries a fork's own
  identity, so it is a per-fork, per-machine artifact and never a WinuX release asset.

## Later - one workflow on every system

WinuX is the Windows part of a larger goal: a fully working configuration project for every
operating system the maintainer uses, with the same workflow, the same habits and the same
configuration ideas on each. A macOS sibling project is in progress; an Arch Linux sibling
follows it; further Linux distributions may come later. The maintainer's personal dotfiles
repository is then a fork of all of them at once - one downstream, several upstreams - holding
one approach on pure Unix, macOS and Windows.

That only works if the upstreams cannot break one another. Each one owns its own platform's
tree and nothing else: a change for Unix lands on every Unix system, a macOS specific lives only
in the macOS tree, a Windows specific only in the Windows tree. Merging one upstream never
touches another's files, so a release of any of them is safe to take on its own.

What the siblings share, and what WinuX already keeps portable for that reason:

- **The configuration concepts** - machine types, projects, workspaces, browser groups, symbolic
  links and package lists are ideas, not Windows features. The sibling projects use the same
  names and the same hierarchical shape, so a fork reads one mental model everywhere.
- **The fork model** - a personal fork, a local override, machine-local overlays and an area for
  the fork's own code, so that an upstream merge is never a conflict with your identity.
- **The shared payloads** - configuration files that apply on more than one system are kept
  platform-neutral; the generic `Git/.gitconfig` already includes `~/.gitconfig.local` last so
  every system can layer its own values on it.
- **The documentation structure and the AI system** - the same page types, the same man-style
  function reference, and the same provider-agnostic context layout.

WinuX itself stays Windows-only. The sibling projects live beside it rather than inside it, and
the shared concepts are documented once in a cross-platform contract page as the siblings reach
them. Nothing on this list changes the Windows contract; it constrains what new Windows features
look like, so that a concept added here can be mirrored on the other systems.

> [!NOTE]
> Ideas and contributions that move any of these forward are very welcome. See the
> [Fork Model](contributing/fork-model.md) and the project's
> [CONTRIBUTING.md](https://github.com/IvanPavlak/WinuX/blob/master/CONTRIBUTING.md).
