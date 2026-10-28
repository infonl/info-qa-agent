# INFO QA agent

An AI teammate for your testers. Every weekday morning it looks at the pull requests merged the day before,
reads their tickets, tests the changes in the browser on your test environment, and posts a short message
to Slack:

> Morning! I tested yesterday's changes on dev. The new error page for the inbox works nicely, but the
> document card still overlaps the side menu on a narrow screen (ABC-1234), could someone take a look? The
> rest were backend refactors, nothing to click there. [Read my full report here](#).

The link opens the full report in GitHub: a verdict per ticket, the bugs with steps and screenshots, and
what a person should still check. The tests the agent wrote, with screenshots and traces, are attached to
the run.

It supports testers; it never blocks a merge or a release. An honest "needs a human" is a valid outcome.

**Plugging it into a project takes no code**: a short workflow, a test user, and a markdown file that
tells the agent about your application.

## How it works

```
QA job                                                               report job (fresh runner)
┌──────────────────────────────────────────────────────────────┐     ┌────────────────────────────┐
│ 1 gather: merged PRs, diffs, Jira tickets (a script, no AI)  │     │ job summary (full report)  │
│ 2 agent: reads your .qa-agent/*.md, logs in, triages,        │ ──► │ Slack message              │
│          writes and runs Playwright tests, writes a report   │     └────────────────────────────┘
│ 3 cleanup: a second session writes a script from cleanup.md, │
│            and the action runs it                            │
│ 4 upload: report, screenshots, traces, tests                 │
└──────────────────────────────────────────────────────────────┘
```

- The agent is GitHub Copilot CLI with Claude Haiku 5.5, billed to your GitHub organization. No AI vendor
  account or API key is needed.
- Dependency updates (Renovate, Dependabot) and PRs that don't touch application code are skipped before
  the agent starts, so they cost nothing.
- Everything about your application lives in your own repository, as markdown in a `.qa-agent/` folder.
  The agent writes all the code it needs itself: the login, the tests, the cleanup.

## What you need

- A web application with a test environment that GitHub-hosted runners can reach (or can be made to reach,
  for example by opening a firewall first; see "Setup steps of your own" below).
- A test user on that environment with a password login (a second one is optional). SSO with 2FA won't
  work.
- GitHub Copilot Business or Enterprise in the organization, with:
  - **Copilot CLI** enabled, and the policy **"Allow use of Copilot CLI billed to the organization"** on
    (organization Settings → Copilot → Policies);
  - the model **Claude Haiku 5.5** enabled (same page, models). Enable Claude Sonnet 5.5 too if you want
    the stronger model for manual runs.
- Optional: a Slack channel, and Jira Cloud for the acceptance criteria of tickets.

## Setup

### 1. Describe your application in `.qa-agent/instructions.md`

Copy [`examples/.qa-agent/`](examples/.qa-agent) to the root of your repository and rewrite it. It's plain
markdown; the agent reads every `.md` file in the folder at the start of a run.

| File | What |
|---|---|
| `instructions.md` | What the application is, **how to log in**, the main pages, the test users and what they may do, how to create test data, and what never to touch. |
| `cleanup.md` | Optional, recommended. Which test data to remove or close after a run, and how (pages or API calls). After every run, even a failed one, a short second agent session writes a cleanup script from it, and the action runs that script. |

The agent works without these files too, by reading your README and source, but slower and less accurately.

Tips, learned from the first runs:

- **Describe the login step by step**: the URL, the field labels and the button. The agent writes its login
  from it, and checks it first; when the login fails, it reports "I couldn't log in today" instead of a
  list of false failures.
- **Give exact locators for tricky flows**, such as a form with icons, comboboxes that load slowly or
  elements with the same text. Plain steps are enough for most pages, but for these the agent loses its
  attempts on guessing. A line like ``page.locator("div").filter({ hasText: /^person$/ }).click()`` is still
  markdown, and the agent copies it.
- **List the main pages with their paths.** It saves the agent many turns of searching.
- **Say where the UI labels are**, for example the translation file for the browser locale you test with.
- **Be honest about the rights of the test users.** If you don't know them exactly, say so. The agent then
  marks "users without right X" tickets as needs-human instead of reporting a false bug.
- **Mark test data clearly**, for example with a "QA Agent:" prefix, so the cleanup can find it and your
  team recognizes it.
- **Keep the agent creating little data**: say "one record per spec file, in `test.beforeAll`".
- **Mention delays in `cleanup.md`**, for example when a search index updates a few seconds later.
- **Never mention cost or budget.** A small model takes it literally and starts skipping tests.

### 2. Add secrets

On the repository (or the environment the workflow uses):

| Secret | What |
|---|---|
| `QA_USERNAME`, `QA_PASSWORD` | The test user. Optionally `QA_USERNAME_2`, `QA_PASSWORD_2` for a second one. |
| `QA_AGENT_SLACK_WEBHOOK_URL` | Optional, see step 3. |
| `QA_AGENT_JIRA_EMAIL`, `QA_AGENT_JIRA_API_TOKEN` | Optional, see step 4. |

The agent's tests read the credentials from environment variables; the agent itself never sees the values.

### 3. Slack (optional)

1. At [api.slack.com/apps](https://api.slack.com/apps): **Create New App → From scratch**, and give it a
   name and an avatar (Basic Information → Display Information).
2. **Incoming Webhooks** → on → **Add New Webhook to Workspace** → pick the channel. This adds the only
   scope the app needs, `incoming-webhook`. If your workspace requires approval for apps, an admin approves
   it first.
3. Save the webhook URL as the secret `QA_AGENT_SLACK_WEBHOOK_URL`.

Without the webhook, the report still appears in the job summary.

### 4. Jira (optional)

With Jira the agent tests against the ticket text and its acceptance criteria; without it, against the PR
description and the diff.

1. Create a token at [id.atlassian.com → Security → API tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
   Use **"Create API token"**, not the one "with scopes": scoped tokens only work through Atlassian's API
   gateway. The account only needs to view the project; the action never writes to Jira.
2. Save it as `QA_AGENT_JIRA_API_TOKEN`, and the e-mail address of the account as `QA_AGENT_JIRA_EMAIL`.
3. Set `jira-base-url` and `jira-project-keys` in the workflow. PRs are linked to tickets through keys in
   their title, branch name or description.

For a sub-task, the action also reads the description of its parent story, because that's usually where
the acceptance criteria are.

### 5. Add the workflow

Copy [`examples/workflow.yml`](examples/workflow.yml) to `.github/workflows/qa-agent.yml` and adjust the
lines marked `ADJUST`. It's about 25 lines and calls the reusable workflow of this repository, which runs
both jobs. Keep `copilot-requests: write`, so Copilot is billed to the organization.

#### Setup steps of your own

When your test environment needs steps before it can be reached, such as opening a firewall, use the
action directly in your own job instead: copy
[`examples/workflow-with-setup.yml`](examples/workflow-with-setup.yml). Keep:

- `fetch-depth: 0` on the checkout, so the diffs can be read;
- the **separate report job**. The agent can write anywhere on its own runner, so the Slack webhook must
  only exist on a fresh one;
- clearing any cloud login before the action runs (see Security).

### 6. Let the agent improve its instructions (optional)

When a project file was missing something or was wrong, and that cost the agent a failed attempt, it can
propose a fix: the report action then opens a draft PR that changes only `.qa-agent/*.md`, with what failed
and why in the description. Every run updates the same PR instead of opening a new one. A person always
reviews and merges it.

Turn it on with `suggest-instructions: true` on the report action, and give the report job
`contents: write` and `pull-requests: write`. The repository setting "Allow GitHub Actions to create and
approve pull requests" (Settings → Actions → General) must be on. This works with the actions directly
(`workflow-with-setup.yml`), not yet with the reusable workflow.

### 7. First run

The "Run workflow" button only appears once the workflow is on the default branch. To try it from a branch
first, add a temporary trigger and remove it before merging:

```yaml
on:
  push:
    branches: [your-branch] # TEMPORARY
```

Every push to that branch then starts a run. Leave Slack out of the first runs (don't set the webhook
secret yet), read the job summary and the agent's transcript (`output/session.md` in the artifact), and
tune `instructions.md` until the report is something your testers trust.

## Inputs

### Reusable workflow `infonl/info-qa-agent/.github/workflows/qa-agent.yml`

Inputs: `app-url` (required), `scope`, `model`, `language`, `locale`, `project-dir`, `base-branch`,
`app-paths`, `max-prs`, `jira-base-url`, `jira-project-keys` (as for the action below), and
`timeout-minutes` (default 60).

Secrets: `username`, `password`, `username-2`, `password-2`, `jira-email`, `jira-api-token`,
`slack-webhook-url`, all optional.

### Action `infonl/info-qa-agent`

| Input | Default | What |
|---|---|---|
| `app-url` | required | URL of the test environment; Playwright's `baseURL` in the agent's tests. |
| `username`, `password` | empty | The test user, as `QA_USERNAME` and `QA_PASSWORD` for the tests. |
| `username-2`, `password-2` | empty | Optional second test user, as `QA_USERNAME_2` and `QA_PASSWORD_2`. |
| `scope` | `yesterday` | `yesterday` (the previous working day; on Monday Friday to Sunday), `<N>d`, or `since:YYYY-MM-DD`. |
| `model` | `claude-haiku-5.5` | Copilot model. `claude-sonnet-5.5` is stronger and about 20 times more expensive. |
| `language` | `English` | Language of the Slack message. |
| `locale` | `en-US` | Browser locale of the tests, e.g. `nl-NL`. |
| `project-dir` | `.qa-agent` | Folder with your markdown files. |
| `base-branch` | `main` | Branch the PRs are merged into. |
| `app-paths` | `.` | Regex. A PR is tested only when it changes a file matching it, e.g. `^src/main/`. |
| `skip-authors` | Renovate and Dependabot | Comma separated PR authors to skip. |
| `max-prs` | `15` | Maximum PRs per run, newest first. The rest are listed as skipped. |
| `jira-base-url`, `jira-project-keys` | empty | Optional Jira Cloud settings. |
| `jira-email`, `jira-api-token` | empty | Optional Jira credentials. Only used before the agent starts. |
| `github-token` | `github.token` | Token for reading PRs and for Copilot. |

Output: `pr-count`, the number of PRs the agent tested. When it is `0`, nothing ran; skip the report job.

### Action `infonl/info-qa-agent/report`

| Input | Default | What |
|---|---|---|
| `slack-webhook-url` | empty | Without it, only the job summary is written. |
| `jira-base-url`, `jira-project-keys` | empty | Turns ticket keys in the Slack message into links. |
| `scope`, `model` | | Shown in the summary. |
| `suggest-instructions` | `false` | Open a draft PR with the agent's suggested improvements to the markdown files; see setup step 6. |
| `project-dir` | `.qa-agent` | Folder with the markdown files, for the suggestions. |
| `github-token` | `github.token` | Token for the suggestion PR. |

## Cost

Through Copilot, Claude Haiku 5.5 costs $0.10 per million input tokens and $0.50 per million output
tokens. A run on a busy day (15 PRs, 35 browser tests, about 30 minutes) used about 9 AI credits, which is
$0.09. Days without testable PRs cost nothing; the agent doesn't even start.

The job's timeout caps the cost. The action deliberately doesn't set Copilot's credit limit: with it, the
model kept telling itself the budget was tight and skipped tests, even far below the limit.

The job summary shows the credits and model calls of every run.

## Security

- **Credentials.** The test users' credentials are environment variables for the tests the agent writes;
  the agent never sees their values. Use test users that only exist on the test environment. Jira
  credentials are only used before the agent starts, and the Slack webhook only exists in the separate
  report job. The workflow token is redacted from the agent's output.
- **What the agent can do.** Read the repository, create and edit files, run its tests through
  `npm run`, and use the read-only shell commands Copilot CLI allows by default (`cat`, `ls`, `tail`).
  Commands that change or delete files, URL fetching and Copilot's built-in GitHub tools are off.
  Copilot CLI can't limit file writes to a folder, so:
  - `cleanup.md` is restored from git before the cleanup session reads it;
  - the report runs on a fresh runner;
  - an instruction suggestion only takes over `.md` files with plain names into `.qa-agent/`, as a draft
    PR that a person reviews;
  - nothing in the agent's job pushes or deploys.
- **Cloud logins.** Tests the agent writes can run any program on the runner. If your setup logs in to a
  cloud (for example to open a firewall), clear that login before the action runs (`az account clear`)
  and log in again afterwards.
- **Input.** PR descriptions and tickets reach the agent as input. The setup trusts the people who write
  them; don't run it on repositories that accept PRs from outsiders without review.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Model "…" from --model flag is not available` | The model isn't enabled in the organization's Copilot policies. |
| The run is green but Slack says it didn't finish | The agent didn't produce valid results; see `output/session.md` in the artifact. |
| "I couldn't log in today" | Check the credentials, and describe the login more precisely in `instructions.md`. |
| `merge commit of #… not found` | The checkout is shallow; use `fetch-depth: 0`. |
| The agent marks most items "not tested" | Something in the instructions mentions cost or limits. Remove it. |
| The cleanup misses records | Say in `cleanup.md` how to find them, and mention delays such as a search index. See `output/cleanup-log.txt` and `output/cleanup-session.md`. |
| The agent's tests fail on labels | Tell it in `instructions.md` where the labels are and which locale the tests use. |

## Updating

Releases are tagged (`v1`, `v1.1.0`, …). Pin a commit SHA in your workflow, with the version as a comment,
and let Renovate or Dependabot propose updates.
