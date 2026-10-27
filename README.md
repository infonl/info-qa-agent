# INFO QA agent

An AI teammate for your testers. Every weekday morning it looks at the pull requests merged the day before,
reads their tickets, tests the changes in the browser on your test environment, and posts a short message
to Slack:

> Morning! I tested yesterday's changes on dev. The new error page for the inbox works nicely, but the
> document card still overlaps the side menu on a narrow screen (ABC-1234), could someone take a look? The
> rest were backend refactors, nothing to click there.
>
> <sub>15 changes checked · ✅ 9 fine · 👀 3 to look at</sub> **[ Read more ]**

"Read more" opens the full report in GitHub: a verdict per ticket, the bugs with steps and screenshots, and
what a person should still check. The tests the agent wrote, with screenshots and traces, are attached to
the run.

It supports testers; it never blocks a merge or a release. An honest "needs a human" is a valid outcome.

## How it works

```
your workflow job                                                     report job (fresh runner)
┌──────────────────────────────────────────────────────────────┐      ┌────────────────────────────┐
│ checkout ─► your own setup (e.g. open a firewall)            │      │ info-qa-agent/report       │
│   ─► info-qa-agent                                           │ ───► │   job summary ("Read more")│
│        1 gather: merged PRs, diffs, Jira tickets (no AI)     │      │   Slack message            │
│        2 agent: triage, write Playwright tests, run, report  │      └────────────────────────────┘
│        3 cleanup: your cleanup.spec.ts, restored from git    │
│        4 upload: report, screenshots, traces, tests          │
│   ─► your own teardown (e.g. close the firewall)             │
└──────────────────────────────────────────────────────────────┘
```

- The agent is GitHub Copilot CLI with Claude Haiku 5.5, billed to your GitHub organization. No AI vendor
  account or API key is needed.
- Gathering is a plain script. Dependency updates (Renovate, Dependabot) and PRs that don't touch
  application code are skipped before the agent starts, so they cost nothing.
- Everything about your application lives in your own repository, in a `.qa-agent/` folder. This repository
  only holds what all projects share.
- Your secrets stay in your repository. The action runs inside your job, so it can use your environment and
  your setup steps, such as opening a firewall.

## What you need

- A web application with a test environment that GitHub-hosted runners can reach (or can be made to reach,
  for example by opening a firewall in a step before the action).
- One or two test users on that environment, with a password login. SSO with 2FA won't work.
- GitHub Copilot Business or Enterprise in the organization, with:
  - **Copilot CLI** enabled, and the policy **"Allow use of Copilot CLI billed to the organization"** on
    (organization Settings → Copilot → Policies);
  - the model **Claude Haiku 5.5** enabled (same page, models). Enable Claude Sonnet 5.5 too if you want
    the stronger model for manual runs.
- Optional: a Slack channel, and Jira Cloud for the acceptance criteria of tickets.

## Setup

### 1. Add a `.qa-agent/` folder to your project

This repository is public, so any repository can use the action; nothing needs to be granted.

Copy [`examples/.qa-agent/`](examples/.qa-agent) to the root of your repository and adapt the four files.

| File | What | Required |
|---|---|---|
| `instructions.md` | What the application is, its main pages, the test users and what they may do, how to create test data, and project rules (what never to touch). The agent reads it at the start of every run. | yes |
| `helpers.ts` | `login(page, user)` and helpers to create test data. The agent always uses them, so credentials and fragile setup never end up in its tests. Reads credentials from environment variables. | yes |
| `smoke.spec.ts` | One test that only logs in. The agent runs it first; when it fails, it reports "I couldn't log in today" instead of a list of false failures. | yes |
| `cleanup.spec.ts` | Removes or closes the test data the agent created. Runs after the agent, restored from git so the agent can't change it. | no, but recommended |

Tips for `instructions.md`, learned from the first runs:

- **List the main pages with their paths.** It saves the agent many turns of searching.
- **Say where the UI labels are**, for example the translation file for the browser locale you test with.
- **Be honest about the rights of the test users.** If you don't know them exactly, say so. The agent then
  marks "users without right X" tickets as needs-human instead of reporting a false bug.
- **Mark test data clearly**, for example with a "QA Agent" prefix, so your cleanup can find it and your
  team recognizes it.
- **Keep the agent creating little data**: say "one record per spec file, in `test.beforeAll`".
- **Never mention cost or budget.** A small model takes it literally and starts skipping tests.

### 2. Add secrets and variables

On the repository or the environment the workflow uses:

| Name | Kind | What |
|---|---|---|
| the URL of your test environment | variable or secret | Passed to the action as `app-url`. |
| your test user credentials | secrets | Whatever `helpers.ts` reads, passed as `env:` to the action step. |
| `QA_AGENT_SLACK_WEBHOOK_URL` | secret | Optional, see step 3. |
| `QA_AGENT_JIRA_EMAIL`, `QA_AGENT_JIRA_API_TOKEN` | secrets | Optional, see step 4. |

### 3. Slack (optional)

1. At [api.slack.com/apps](https://api.slack.com/apps): **Create New App → From scratch**, name it e.g.
   "QA Agent".
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
3. Pass `jira-base-url` and `jira-project-keys` to both actions. PRs are linked to tickets through keys in
   their title, branch name or description.

For a sub-task, the action also reads the description of its parent story, because that's usually where
the acceptance criteria are.

### 5. Add the workflow

Copy [`examples/workflow.yml`](examples/workflow.yml) to `.github/workflows/qa-agent.yml` and adjust the
lines marked `ADJUST`. Keep:

- `permissions: copilot-requests: write`, so Copilot is billed to the organization;
- `fetch-depth: 0` on the checkout, so the diffs can be read;
- the **separate report job**. The agent can write anywhere on its own runner, so the Slack webhook must
  only exist on a fresh one.

### 6. First run

The "Run workflow" button only appears once the workflow is on the default branch. To try it from a branch
first, add a temporary trigger and remove it before merging:

```yaml
on:
  push:
    branches: [your-branch] # TEMPORARY
```

Every push to that branch then starts a run. Leave Slack out of the first runs (don't set the secret, or
set `post_to_slack` to false), read the job summary and the agent's transcript (`output/session.md` in the
artifact), and tune `instructions.md` until the report is something your testers trust.

## Inputs

### `infonl/info-qa-agent`

| Input | Default | What |
|---|---|---|
| `app-url` | required | URL of the test environment. Available to tests as `QA_APP_URL` and as Playwright's `baseURL`. |
| `scope` | `yesterday` | `yesterday` (the previous working day; on Monday Friday to Sunday), `<N>d`, or `since:YYYY-MM-DD`. |
| `model` | `claude-haiku-5.5` | Copilot model. `claude-sonnet-5.5` is stronger and about 20 times more expensive. |
| `language` | `English` | Language of the Slack message. |
| `locale` | `en-US` | Browser locale of the tests, e.g. `nl-NL`. |
| `project-dir` | `.qa-agent` | Folder with your project files. |
| `base-branch` | `main` | Branch the PRs are merged into. |
| `app-paths` | `.` | Regex. A PR is tested only when it changes a file matching it, e.g. `^src/main/`. |
| `skip-authors` | Renovate and Dependabot | Comma separated PR authors to skip. |
| `max-prs` | `15` | Maximum PRs per run, newest first. The rest are listed as skipped. |
| `jira-base-url`, `jira-project-keys` | empty | Optional Jira Cloud settings. |
| `jira-email`, `jira-api-token` | empty | Optional Jira credentials. Only used before the agent starts. |
| `github-token` | `github.token` | Token for reading PRs and for Copilot. |

Output: `pr-count`, the number of PRs the agent tested. When it is `0`, nothing ran; skip the report job.

### `infonl/info-qa-agent/report`

| Input | Default | What |
|---|---|---|
| `slack-webhook-url` | empty | Without it, only the job summary is written. |
| `jira-base-url`, `jira-project-keys` | empty | Turns ticket keys in the Slack message into links. |
| `scope`, `model` | | Shown in the summary. |

## Cost

Through Copilot, Claude Haiku 5.5 costs $0.10 per million input tokens and $0.50 per million output
tokens. A run on a busy day (15 PRs, 35 browser tests, about 30 minutes) used about 9 AI credits, which is
$0.09. Days without testable PRs cost nothing; the agent doesn't even start.

The job's `timeout-minutes` caps the cost. The action deliberately doesn't set Copilot's credit limit:
with it, the model kept telling itself the budget was tight and skipped tests, even far below the limit.

The job summary shows the credits and model calls of every run.

## Security

- **Credentials.** Jira credentials are only used by the gather step, before the agent starts. The Slack
  webhook only exists in the separate report job. The workflow token is redacted from the agent's output.
  Test user credentials are available to the tests the agent writes; use test users that only exist on
  the test environment.
- **What the agent can do.** Read the repository, create and edit files, run its tests through
  `npm run`, and use the read-only shell commands Copilot CLI allows by default (`cat`, `ls`, `tail`).
  Commands that change or delete files, URL fetching and Copilot's built-in GitHub tools are off.
  Copilot CLI can't limit file writes to a folder, so:
  - the cleanup is restored from git before it runs;
  - the report runs on a fresh runner;
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
| `merge commit of #… not found` | The checkout is shallow; use `fetch-depth: 0`. |
| The agent marks most items "not tested" | Something in the instructions mentions cost or limits. Remove it. |
| The cleanup reports open records it just closed | Search indexes update asynchronously; poll in `cleanup.spec.ts` (`expect.poll`). |
| The agent's tests fail on labels | Tell it in `instructions.md` where the labels are and which locale the tests use. |

## Updating

Releases are tagged (`v1`, `v1.1.0`, …). Pin a commit SHA in your workflow, with the version as a comment,
and let Renovate or Dependabot propose updates.
