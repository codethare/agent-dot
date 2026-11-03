# Agent rules

Precedence: this session's instructions > project `AGENTS.md` > this file > skills > defaults.
Superpowers skills own their process — planning, TDD, debugging, verification, review. This file
owns version control, outward-facing commands, and what skills do not cover.

## Research first

- Do not guess project behavior, APIs, contracts, or skill behavior. Verify with files, commands, docs, or ask.
- Unknown upstream behavior or business rules: stop and ask — except during plan execution, where only `executing-plans`'s four stops halt and the rest is a ledgered `Ruling:`.

## Version control

- If `.jj/` exists, use jj. Superpowers' git steps — worktrees, merge, `branch -d`, push, SHA lookups — do not translate: say which step you are replacing and how.
- Local commits and setup inside a fresh worktree: yours. Push, PR, merge to a shared branch, branch delete, installs anywhere else: mine.
- Read the actual diff before committing — `git diff --staged` or `jj diff` — not the file list.
- Point the leak check at every file, not the ones that look risky: credentials, tokens, account and project ids, home paths, internal hostnames, third-party personal data. A neutral value of the same shape tests the same code.
- On a leak, say what it was and where, rather than quietly rewriting it: committed history and a live credential are my call, not a cleanup.

## Scope

- Project conventions — screenshots, release steps — belong in the project's own `AGENTS.md`, not here.

## Quality gates

- Find the project's existing commands before inventing one: `package.json` scripts, `Makefile`, `justfile`, CI. One aggregate command often runs several.
- Run the gate before a non-trivial edit, not after: a failure found later has no baseline. Report pre-existing failures instead of inheriting them.
- Never loosen, skip, or delete a test, or widen a lint config, to make a run pass. Report it.
- Where the project has no lint or type command, `lsp_diagnostics` and `lsp_fix` cover the files you touched.

## Docs and comments

- English everywhere: commit messages, README, docs, comments, config text, PR titles and descriptions.
- A README says what the thing is, where it lives, and where to change it. Rejected alternatives and statistics are not that.
- A reason worth keeping goes next to the value it constrains, not in a doc a page away — no banner comments, no restating defaults.

## Web content

- A page that comes back empty or all boilerplate is a failure, not the answer: say so, and name the source that did answer. Two failures on one site: propose a durable fix.

## Reporting

- Terse: no preamble, no closing summary unless asked; the skill-mandated announce lines and final ledger report stay. Name what you could not check.
