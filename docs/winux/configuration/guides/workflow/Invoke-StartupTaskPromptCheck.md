# Invoke-StartupTaskPromptCheck

The prompt function `Register-StartupTaskPromptCheck` installs: the original prompt, plus the once-a-day startup tasks at the first prompt after the day starts.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure. Which tasks it runs, and when a day starts, is set on the [`Invoke-StartupTasks`](Invoke-StartupTasks.md) guide (`Trigger = "TerminalOpen"`, `Frequency = "OncePerDay"`, `DayStartHour`).

## Usage

```powershell
# Not called by hand: Register-StartupTaskPromptCheck makes it the body of the prompt function
Invoke-StartupTaskPromptCheck
```

It runs the original prompt first and keeps its text, then - once the recorded day boundary has passed - runs `Invoke-StartupTasks -Trigger TerminalOpen` and moves the boundary on. The tasks print before the prompt text is returned, so the prompt is drawn below them. It never throws, and it puts `$LASTEXITCODE` back, so nothing a task ran shows up as the exit code of your last command.

It replaces the deprecated [`Invoke-RepositoryUpdatePromptCheck`](../git/Invoke-RepositoryUpdatePromptCheck.md).

## Related

- [`Invoke-StartupTaskPromptCheck` in the Workflow module reference](../../../modules/workflow.md#invoke-startuptaskpromptcheck) - parameters, usage and behaviour
- [`Register-StartupTaskPromptCheck`](Register-StartupTaskPromptCheck.md) - installs it
- [Workflow configuration guides](README.md) - every guide for this module
