______________________________________________________________________

## allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git blame:*), Bash(git rev-parse:\*) description: Code review local git diff changes

Provide a code review for local git changes.

**Arguments:** `$ARGUMENTS` (optional commit range, e.g., `HEAD~3..HEAD`, `main..feature`, or empty for unstaged changes)

To do this, follow these steps precisely:

1. Determine the diff to review based on arguments:

   - If `$ARGUMENTS` is empty: review unstaged changes (`git diff`)
   - If `$ARGUMENTS` is `--staged`: review staged changes (`git diff --staged`)
   - If `$ARGUMENTS` contains a commit range (e.g., `HEAD~3..HEAD`, `main..feature`): review that range (`git diff <range>`)
   - If `$ARGUMENTS` is a single commit: review changes introduced by that commit (`git show <commit>`)

1. Launch a haiku agent to check if there are any changes to review. If no changes found, stop and inform the user.

1. Launch a haiku agent to return a list of file paths (not their contents) for all relevant CLAUDE.md files including:

   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified in the diff

1. Launch a sonnet agent to view the diff and return a summary of the changes

1. Launch 4 agents in parallel to independently review the changes. Each agent should return the list of issues, where each issue includes:

   - File path and line number(s)
   - Description of the issue
   - Reason it was flagged (e.g., "CLAUDE.md adherence", "bug", "security")

   The agents should do the following:

   Agents 1 + 2: CLAUDE.md compliance sonnet agents
   Audit changes for CLAUDE.md compliance in parallel. Note: When evaluating CLAUDE.md compliance for a file, you should only consider CLAUDE.md files that share a file path with the file or parents.

   Agent 3: Opus bug agent (parallel subagent with agent 4)
   Scan for obvious bugs. Focus only on the diff itself without reading extra context. Flag only significant bugs; ignore nitpicks and likely false positives. Do not flag issues that you cannot validate without looking at context outside of the git diff.

   Agent 4: Opus bug agent (parallel subagent with agent 3)
   Look for problems that exist in the introduced code. This could be security issues, incorrect logic, etc. Only look for issues that fall within the changed code.

   **CRITICAL: We only want HIGH SIGNAL issues.** This means:

   - Objective bugs that will cause incorrect behavior at runtime
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken

   We do NOT want:

   - Subjective concerns or "suggestions"
   - Style preferences not explicitly required by CLAUDE.md
   - Potential issues that "might" be problems
   - Anything requiring interpretation or judgment calls

   If you are not certain an issue is real, do not flag it. False positives erode trust and waste reviewer time.

1. For each issue found in the previous step by agents 3 and 4, launch parallel subagents to validate the issue. The agent's job is to review the issue to validate that the stated issue is truly an issue with high confidence. For example, if an issue such as "variable is not defined" was flagged, the subagent's job would be to validate that is actually true in the code. Another example would be CLAUDE.md issues. The agent should validate that the CLAUDE.md rule that was violated is scoped for this file and is actually violated. Use Opus subagents for bugs and logic issues, and sonnet agents for CLAUDE.md violations.

1. Filter out any issues that were not validated in step 6. This step will give us our list of high signal issues for our review.

1. Output the review to the terminal in a clear, actionable format:

______________________________________________________________________

## Local Code Review

**Diff reviewed:** `[describe what was reviewed - e.g., "unstaged changes", "HEAD~3..HEAD", etc.]`

### Summary

[Brief summary of the changes from step 4]

### Issues Found

[If issues found, list each one:]

**Issue 1:** [Brief title]

- **File:** `path/to/file.ext` (lines X-Y)
- **Type:** [bug/CLAUDE.md violation/security]
- **Description:** [Clear description of the issue]
- **Suggested fix:** [How to fix it]

[Repeat for each issue]

[If NO issues found:]
No issues found. Checked for bugs and CLAUDE.md compliance.

______________________________________________________________________

Use this list when evaluating issues in Steps 5 and 6 (these are false positives, do NOT flag):

- Pre-existing issues not in the diff
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns (e.g., lack of test coverage, general security issues) unless explicitly required in CLAUDE.md
- Issues mentioned in CLAUDE.md but explicitly silenced in the code (e.g., via a lint ignore comment)

Notes:

- Create a todo list before starting.
- If referring to a CLAUDE.md rule, quote it directly.
- Focus on actionable feedback that helps the developer improve the code before committing.
