# Roadmap

WinuX is an early-stage project with a clear destination: a deeply configurable Windows 11
distribution that **anyone** can install and use - not just terminal power users.

This page is a high-level view of where the project is and where it's headed. It is intentionally
direction-over-dates - priorities shift as contributors get involved. For shipped changes see the
[CHANGELOG](https://github.com/IvanPavlak/WinuX/blob/master/CHANGELOG.md); for how versions are
numbered see [VERSIONING](https://github.com/IvanPavlak/WinuX/blob/master/VERSIONING.md).

## Where WinuX is today

Today WinuX is **terminal- and keyboard-driven**, built for power users comfortable editing a
PowerShell configuration file. From a single `Configuration.psd1` (plus a personal
`Configuration.local.psd1` override) one command provisions a whole machine: system settings,
software, dotfiles, repositories, and window workspaces. It is tested across VMware and real
machines, with a full Pester suite and a man-style reference for every function.

What it is **not yet**: approachable for someone who has never opened a terminal. That is the gap
the roadmap closes.

## Guiding principles

- **Configurability is never sacrificed.** Every layer added for newcomers (installer, GUI) sits
  *on top of* the declarative config - it never replaces or hides it.
- **One source of truth.** The documentation and `Configuration.psd1` describe the whole system;
  no behavior is hidden.
- **Reproducible and idempotent.** Re-running anything is always safe.
- **No personal data in the project.** Your identity and paths live only in your local override.

## Now

- Open-sourcing groundwork: license, governance, contribution flow, CI, and public documentation.
- A generic, VM-ready default profile so anyone can try WinuX safely in a virtual machine.
- A personal-fork model so a maintainer's own machine and the public project share a single source
  of truth; see the [Fork Model](contributing/fork-model.md) page.

## Next

- **Guided installer** - an interactive first-run experience that asks the essential questions
  (identity, machine type, which app sets) and writes your `Configuration.local.psd1` for you,
  instead of hand-editing a file.
- **Configuration validation** - friendly, actionable errors when a config is incomplete or
  inconsistent, rather than failures at runtime.
- **Example profiles** - beyond `Test`, common setups people can start from, with feature-flag-like gates for seamless (de)activation.

## Later

- **Graphical UI** - a visual front-end for the things most users want (choosing software, themes,
  wallpapers, taskbar, window layouts) that reads and writes the *same* configuration the CLI uses.
- **Broader hardware and locale coverage**, validated by the community.

## Toward 1.0

WinuX reaches **1.0** when a non-technical user can go from a fresh Windows 11 install to a fully
configured machine through a guided, mostly graphical experience while power users keep every bit of the configurability that defines the project. This includes software installation, workspace orchestration, and everything else a power user can do now.

> [!NOTE]
> Ideas and contributions that move any of these forward are very welcome. See the
> [Fork Model](contributing/fork-model.md) and the project's
> [CONTRIBUTING.md](https://github.com/IvanPavlak/WinuX/blob/master/CONTRIBUTING.md).
