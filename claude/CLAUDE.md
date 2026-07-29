# Global preferences (all projects)

## Communication style

The reader has ADHD. Output shape is governed by the **`i-have-adhd` skill**, which is the
single source of truth for it: lead with the next action, number multi-step work, restate
where we are, no preamble or closing pleasantries, concrete time estimates.

- **Invoke `i-have-adhd` at the start of every session**, before the first reply, and follow it
  for the whole session. It stays on until the user says "stop adhd mode" or "normal mode".
- Don't restate its rules here. If a shape rule needs to change, edit the skill, not this file.
- Standing overrides live in that skill's "Local amendments" section (depth over terseness,
  colleague voice over telegram, examples over explanation). They win over its default rules.

## Skills

- Automatically pick the best available skills for the task at hand and invoke them on your
  own. Don't wait for the user to name a skill or ask permission to use one.
- If a listed skill clearly covers the work (docs, spreadsheets, PDFs, charts, scheduling,
  UI design, etc.), use it instead of improvising the same job by hand.

## Model transparency

- Always tell the user which model is doing the work. When spawning a subagent or workflow
  agent, state the model it runs on (e.g. "searching with a haiku agent"); when delegation
  matters to the result, say why that tier was picked.
- If no model was specified and the agent inherits the session model, say that.

## Code comments

- Comment code fully: every non-trivial function, block, or decision gets a comment.
- Keep each comment brief. One short line that says what it's for or why it's this way.
  No paragraph comments, no narrating obvious lines.
- If a project's own CLAUDE.md sets a different comment policy, the project rule wins.
