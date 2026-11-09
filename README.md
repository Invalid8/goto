# goto

My personal bash command for jumping between project folders. Not a package, not published anywhere.

## Why

I live across `~/Projects/{Web,Work,Mobile,Desktop,Packages,...}`, with a lot of client and personal
projects spread between them. `goto` started as a tiny function in `.bashrc` that read `~/.goto_dirs`, which
held 12 shortcuts: `projects`, `web`, `mobile`, `desktop`, `brainstorm`, `work`, `workspace`, `packages`,
`backend`, `school`, `freelance` and `de`.

My shell history showed how I actually used it. `goto web` ran 87 times and `goto work` 65. The shortcuts
only reached the category folders, so most jumps ended with another `cd` into the same few client projects,
85 times for the top three alone, plus lines like `goto web && cd fillyr` and
`goto mobile && cd baseband`. Typos such as `goto worj` and `goto we` just failed.

On 1 Nov 2026 I rebuilt it:

- 42 shortcuts, covering the projects themselves and not only the categories
- any folder under `~/Projects` reachable by name, with no shortcut needed
- partial names, matched exact → prefix → contains
- a pick menu when several folders match, ranked by how often I visit each one
- `goto <name> <subdir>` to land inside a project
- `goto add`, `rm`, `recent`, `edit` and `help`
- `goto code <name>` and `goto zed <name>` to jump and open the editor
- Tab completion for names, subcommands and subfolders

My reaction: "this is much much more".

## Day to day

```sh
goto baseband             # ~/Projects/Mobile/baseband
goto baseband app         # straight into its app folder
goto cosmic-ios           # no shortcut needed, prefix finds ~/Projects/Desktop/cosmic-ios-runner
goto fission              # ~/Projects/Desktop/fission
goto code cheerkit        # jump and open in VS Code
goto zed vscribe          # ~/Projects/Desktop/vn-transcribe in Zed
goto web                  # the category folders still work as before
goto recent               # pick from the last 15 places
goto add notes            # save the current folder as a shortcut
```

Several matches give a menu, with the folders I visit most at the top:

```
$ goto cosmic
1) ~/Projects/Desktop/cosmic-editor
2) ~/Projects/Desktop/cosmic-studio
3) ~/Projects/Desktop/cosmic-recorder
4) ~/Projects/Desktop/cosmic-studio-planning
5) ~/Projects/Desktop/cosmic-ios-runner
goto>
```

`goto we` now opens a menu headed by `~/Projects/Web` instead of failing. `goto worj` still finds nothing,
since matching is by prefix and substring, not fuzzy spelling.

## Usage

```
goto <name> [subdir]   jump to a shortcut or any project folder (prefix/partial names work)
goto                   list shortcuts
goto add <name> [dir]  save a shortcut (defaults to the current folder)
goto rm <name>         remove a shortcut
goto recent            pick from recently visited folders
goto code <name>       jump and open in VS Code
goto zed <name>        jump and open in Zed
goto edit              edit the shortcut file
```

A name resolves in this order:

1. an exact shortcut in `~/.goto_dirs`
2. a folder under `~/Projects` with exactly that name, searched two levels deep plus one more inside
   folders that hold only other folders, such as `~/Projects/Web/design-enginering/my-showcase`
3. shortcuts and folders whose name starts with it
4. shortcuts and folders whose name contains it

The first stage with any match wins. One match jumps straight there; more than one opens the menu.

## Files

| Path | What |
| --- | --- |
| `goto.sh` | the function and its completion, sourced by `.bashrc` |
| `install.sh` | sets everything up, safe to run again |
| `dirs.example` | a starter shortcut list (my real one stays private in `~/.goto_dirs`) |
| `~/.config/goto/goto.sh` | symlink to `goto.sh` in this repo, so edits here are live in new shells |
| `~/.goto_dirs` | my shortcuts, one `name=~/path` per line |
| `~/.goto_history` | every visit, used for ranking and `goto recent` (last 1000 kept) |

Settings such as the search roots, depth and recent count are the variables at the top of `goto.sh`.

## Install

```sh
./install.sh
```

It links `~/.config/goto/goto.sh` to this repo, adds `. "$HOME/.config/goto/goto.sh"` to `~/.bashrc` if
it isn't there, and creates `~/.goto_dirs` from `dirs.example` if that file doesn't exist. An existing
shortcut file is never touched. Open a new shell afterwards.
