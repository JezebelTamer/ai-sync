# Global preferences (all projects)

## Precedence and standing overrides

- Highest first: **live user message > project CLAUDE.md > this file > skills > harness
  defaults.** Nothing lower may quietly relax a rule stated higher.
- **Safety outranks efficiency and style at every level.** No brevity, speed, or cost rule
  overrides a production, destructive, or irreversible warning from anywhere. Safety beats
  rules, never the user.
- **Never add a Claude or Anthropic `Co-Authored-By` trailer, in any repo.** Overrides the
  harness default that asks for one.
- **Work lands on the checked-out branch.** No `git checkout -b`, no worktree, unless asked.
  Consent to work on `main` is standing, so skills that demand isolation are overridden here.
  Do not spend a turn asking.
- **Facts and invariants live in a CLAUDE.md; procedures live in a skill.** CLAUDE.md is billed
  every turn, a skill body loads only when used. Keep a skill under 5k tokens with the critical
  instruction in the first paragraph, since post-compaction re-injection truncates the tail.

## Output shape

- **Invoke `i-have-adhd` before the first reply of every session** and follow it until the user
  says "stop adhd mode" or "normal mode". Its "Local amendments" outrank its own defaults.
- **Re-invoke it after any compaction.** The invocation lives in the message history that
  compaction replaces, so shape degrades silently without this.
- Durable core, in case the skill body is ever truncated: lead with the next action, restate
  where we are every turn, no preamble and no closing pleasantries, and brevity comes from
  cutting filler, never from cutting the *why*.
- **Name the model on every dispatch**, inherited ones included, and name the skill you used.
  Both ride as a parenthetical on the dispatch line or one trailing line, never the opener.
- **Invoke a skill when it names the artifact you are producing, or when you are about to
  hand-roll a procedure it owns.** Do not wait to be asked.
- **Use the todo tool for multi-step work.** It is the cheapest state restatement available; do
  not also narrate the plan as prose.

## The floor: what token savings never buy

- **The metric is fewest tokens to a verified result, not fewest per turn.** Before taking a
  cheaper path, ask what it costs when it is wrong. Wrong more than about one time in five means
  the expensive path was the cheap one. Rework dwarfs retrieval, so nothing here licenses
  skipping exploration that prevents a wrong pass.
- **Efficiency governs input, not the reader.** It covers files read, output captured,
  exploration breadth, and subagent count. Restating state, the *why*, the next action, and what
  now works stay in full. The one output rule: never echo file contents back, and never
  re-narrate a diff you just applied.
- **Never economize on reasoning.** Thinking before a tool call is the main lever on the *number*
  of tool calls, and tool results are where the tokens are.
- **Never cap output while enumerating.** Capping is for sampling a shape. When listing things
  you must change or verify, take the whole list, or count first and state the total. A truncated
  result reads exactly like "no further matches."
- **A green build and green tests are not evidence the app works.** See Verification.

## Autonomy and the risk lane

- **Do not ask permission for ordinary commands or edits.** Proceed, then report. A needless
  confirmation is two full round trips carrying the whole conversation.
- **Confirm first only for this closed list:** production data or schema writes, DB migrations,
  deploys, any `git push`, force push, `rm -rf`, mass DELETE/UPDATE, publishing, and anything
  the project CLAUDE.md flags.
- **"No permission-seeking" is not "no questions."** An ambiguous *goal* gets one short question
  before the work, not after.
- Size the lane before starting, and say which one you are in:
  - **Trivial** (single file, no behavior change): edit, targeted check, done. No plan statement,
    no full suite, no smoke test.
  - **Normal:** state the plan and the verification target, then work the loop below.
  - **Risky** (production data, schema, routing, startup, DI, config, auth): confirm first, and
    finish with the app-level smoke test.
- **CBS-Dashboard's dev config points at real production databases.** Every write, migration, and
  deploy there is risky-lane. Paste that warning verbatim into every subagent prompt sent into
  that repo: the built-in Explore and Plan agents do not read CLAUDE.md files at all, so a
  dispatched agent has no other way to learn it.

## Delegation

- **Default posture is orchestrator.** Scope it, write a self-contained prompt, dispatch, verify
  the result yourself. Prefer delegating implementation over editing files in the main turn.
- **Do it yourself when verification needs a signed-in browser, a running app, or judgment a
  subagent cannot exercise.**
- **Always name the model on dispatch.** An omitted `model` inherits the session model, the most
  expensive tier here. Tier by invariant density, not apparent size: `haiku` for work checkable
  by exact match (renames, formatting, bulk find/replace, file and log inventory, scanning a
  captured run), `sonnet` for routine implementation against a clear spec in a tested area, top
  tier for invariants, schemas, production data, security, root-cause debugging, design calls.
- **If trusting the result would mean reading the whole diff line by line, the tier was too
  weak.** Escalating mid-task is free. A subagent that is unsure stops and reports, never guesses.
- **Prompts are an investment.** Every dispatch carries the absolute paths you already found, the
  invariants quoted verbatim, what done looks like, the exact verification command, a cap on what
  comes back ("paths plus one line each, no code"), and orders to report a failure rather than
  diagnose around it.
- **Past roughly 4 parallel agents, state the per-agent scope first.** One module or table per
  agent beats a broad sweep; single broad agents here have run past 200k tokens.
- **Codex is available in the CLI (`sol`, `luna`, etc.) and does not bill Claude usage.** Consult
  it for non-critical work: second opinions, boilerplate, research legwork, sanity checks on an
  approach. It is off-budget, so reach for it before spending a Claude subagent on the same job.
  Keep on Claude anything in the risky lane, anything touching production data or invariants, and
  anything you will not personally verify — the verification rules below still apply to whatever
  Codex hands back.

## Verification

- **Nothing is reported done, and nothing is left standing on the branch, until you personally
  ran the verification.** Subagents committing inside their own scope is fine; your gate is
  "verified before I move on," not "before any commit exists."
- **Verify the outcome, not the narrative.** Run the app, hit the endpoint, inspect the artifact.
  Never verify by re-reading the files the subagent read; that cancels the delegation.
- **If the pass touched routing, static assets, DI, startup, config, or middleware order, run the
  app.** In CBS-Dashboard: load a static asset, `/`, an authorized route (expect 302 to login,
  not 500), and an unmatched URL (expect 404). In MediaBot: `npm run bot` and exercise the path
  you touched. If you genuinely cannot run it, say "smoke test not run" and why. **Subagents
  cannot sign in, so this one is yours.**
- **Before a commit or a completion claim, run the project's default suite, captured to a file.**
  Never enable an opt-in live-data category to do it (CBS-Dashboard's `CBS_LIVE_TESTS=1` hits
  live plant databases). Filtered runs belong to the iteration loop; never say "tests pass" off
  one without naming the subset.
- **A code-change completion claim carries its evidence line:** exact command, exit code,
  pass/fail counts, copied from the captured run rather than recalled.
- **When an agent blames the environment for a failure that appeared this session, assume this
  session caused it until disproved.** That misdiagnosis has already cost a full session here.

## Context cost

- **Context is rent charged every turn**, not a one-time purchase. Before pulling something large
  in, ask whether you will reference it after this turn. If not, it belongs in a file, a filter,
  or a subagent.
- **Capture expensive command output to a file, then grep the file.** Oversized output is
  auto-previewed from the *front*, so on a test run you get the header and lose every failure
  line, then pay a Read on top. Applies to suites, builds, restores, linters, and eval runners:
  `$out = "$env:TEMP\run.txt"; <cmd> *> $out; "exit=$LASTEXITCODE"; exit 0`
- **Search in escalating specificity:** `count` or `files_with_matches` to size it, then
  `content` with `glob`/`type` and an explicit `head_limit`. Decide point vs survey before the
  first grep; a survey greps every alias repo-wide and enumerates the hits. **If you cannot tell
  which it is, it is a survey.**
- **Read the file you are about to edit**, in full under roughly 500 lines, otherwise imports and
  exports plus the target region. **Never edit a file you only grepped:** the rule that makes an
  edit correct usually lives in the imports, not at the edit site.
- **Always re-read what someone else wrote:** a subagent's diff, anything a build, formatter,
  codegen, or git operation touched. Independent verification means reading the artifact, not the
  report about it.
- **Docs say what to look for, code says what is true.** Confirm the load-bearing fact in source.
  If they disagree, code wins and the doc is a bug to fix in the same pass.
- **Never batch dependent work past a verification point.** Batch independent work freely.
- Cite `path:line` instead of quoting code you only read. Start git inspection at `--stat` or
  `--name-only`. Never open lock files, `node_modules`, `bin/`, `obj/`, minified bundles, or
  generated output.
- **Never change model, effort, plugins, or MCP servers mid-session.** Each is part of the cache
  key, and switching discards the whole cached prefix. Put a subtask's depth in that subagent's
  or skill's frontmatter instead.
- **A filling context window is a symptom of dumping raw output into it.** Fix that first. Before
  the window runs out, write durable state to a scratchpad file: decisions, absolute paths
  touched, the exact verification command, and what is verified versus merely claimed.
- **A CLAUDE.md edit is not live until `/clear`, `/compact`, or restart.** Say so rather than
  acting as though the new rule is in force.
- **When the same correction lands twice, write a `PreToolUse` hook** in `settings.json`. The
  harness enforces a hook; a line in this file only requests one. A memory or preference cannot
  automate anything.

## Environment

- **Windows 10 / PowerShell 5.1.** Run npm, dotnet, tests, and validators from PowerShell.
- **The Bash tool is Git Bash.** Do not run test, pack, or build commands there. A test failing
  on a `tar` / `C:` resolve error means the wrong shell, not a bug.
- **Record the PID of anything you start** and kill it before ending the turn
  (`taskkill /F /T /PID <pid>` for a tree). Never end a turn with a dev server or bot alive.
- **Prefer a CLI (`gh`, `dotnet`, `npm`) over an MCP server** for the same job, and never call a
  connector that has not been authenticated.

## Git

- **Commit each verified iteration**, not one end-of-session commit. A commit is a cheap bisect
  anchor. Stage only the files belonging to the change.
- **Never push to a remote unprompted**, and never force push.

## Code comments

- **Comment code fully:** every function, every non-obvious block, and every deliberate decision
  gets one short line saying what it is for or why it is that way. No paragraph comments, no
  narrating obvious lines.
- A project CLAUDE.md that sets a different comment policy wins.
