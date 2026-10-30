# INFO QA agent

An AI teammate for your testers. Every weekday morning it looks at the pull requests merged the day before,
reads their tickets, tests the changes in the browser on your test environment, and tells your team in
Slack, ticket by ticket, worst first:

> Hey team! This is what I clicked through on dev.
>
> 🐞 **ABC-1234  Document card overlaps the side menu**<br>
> I opened a case with a document and made the screen narrower. From 900px wide the document card covers
> the side menu, so the 'Edit' button disappears. Could someone take a look? There's a screenshot in the
> report.
>
> ✅ **ABC-1236  New error page for the inbox**<br>
> I opened the inbox as a user without the right and got the new error page instead of an empty list.
>
> Not testable in the browser: ABC-1237, ABC-1238
>
> [Read my full report here](#)

The link opens the full report in GitHub: a verdict per ticket, the bugs with steps and screenshots, and
what a person should still check. The tests the agent wrote, with screenshots, are attached to
the run.

It supports testers; it never blocks a merge or a release. An honest "needs a human" is a valid outcome.

**Plugging it into a project takes a short workflow, a test user, and a `.qa-agent/` folder**: a markdown
file that tells the agent about your application, plus optional Playwright hooks for what must work the
same every time, such as logging in and cleaning up.

## How it works

```
QA job                                                               report job (fresh runner)
┌──────────────────────────────────────────────────────────────┐     ┌────────────────────────────┐
│ 1 gather: merged PRs, diffs, Jira tickets (a script, no AI)  │     │ job summary (full report)  │
│ 2 globalSetup.ts: your code, e.g. log in and save sessions   │ ──► │ Slack message              │
│ 3 agent: reads .qa-agent/instructions.md, triages, writes    │     │ optional: draft PR with    │
│          and runs Playwright tests (beforeEach.ts and        │     │ better instructions        │
│          afterEach.ts around each), writes a report          │     └────────────────────────────┘
│ 4 globalTeardown.ts: your code, e.g. clean up test data      │
│ 5 upload: report, screenshots, tests; passwords scrubbed     │
└──────────────────────────────────────────────────────────────┘
```

- The agent is GitHub Copilot CLI with Claude Haiku 5.5, billed to your GitHub organization. No AI vendor
  account or API key is needed.
- Dependency updates (Renovate, Dependabot) and PRs that don't touch application code are skipped before
  the agent starts, so they cost nothing.
- Everything about your application lives in your own repository, in a `.qa-agent/` folder: knowledge as
  markdown, and the steps that must be reliable as Playwright code. The agent writes the tests itself.

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

### 1. Add a `.qa-agent/` folder

Copy [`examples/.qa-agent/`](examples/.qa-agent) to the root of your repository and rewrite it. Every
file is optional; the agent works without them too, by reading your README and source, but slower and less
accurately.

| File | When it runs | What it's for |
|---|---|---|
| `instructions.md` | read by the agent at the start | What the application is, its main pages, the test users and what they may do, how to create test data, and what never to touch. Any other `.md` file in the folder is read too. |
| `globalSetup.ts` | once, before the agent | Log in and save sessions, prepare data. **When it fails, the agent doesn't run**, and the report says it couldn't prepare. |
| `globalTeardown.ts` | once, after the agent, also when it crashed | Clean up the test data the agent created. |
| `beforeEach.ts` | before every test the agent writes | For example open a starting page, or dismiss a cookie banner. |
| `afterEach.ts` | after every test the agent writes | For example check that no error dialog is open. |

Use code for what must work the same every run, and markdown for everything the agent should know. The names
and signatures are Playwright's own:

```ts
// globalSetup.ts and globalTeardown.ts: like Playwright's globalSetup and globalTeardown
import type { FullConfig } from "@playwright/test";
export default async function globalSetup(config: FullConfig) {
  const { baseURL, locale } = config.projects[0].use; // the app-url and locale of the workflow
  // ... launch a browser with chromium.launch(), log in, save sessions
}

// beforeEach.ts and afterEach.ts: the arguments of Playwright's test.beforeEach and test.afterEach
import type { Page, TestInfo } from "@playwright/test";
export default async function beforeEach({ page }: { page: Page }, testInfo: TestInfo) {
  // ...
}
```

The hooks run in a folder next to the agent's tests, so they can import each other (for example a shared
`login`), but not other files of your repository.

**Logging in.** The recommended `globalSetup.ts` logs in each test user and saves their session as
`auth/user1.json` and `auth/user2.json` (see the example). Every test then starts logged in as user 1; a
test switches to user 2 with `test.use({ storageState: "auth/user2.json" })`. Neither the agent nor its
tests get the passwords. Without these sessions, the agent writes a login itself from `instructions.md` and
its tests read the passwords from `QA_PASSWORD` and `QA_PASSWORD_2`.

**Cleaning up.** `globalTeardown.ts` always runs, even after a crash, from the version in git, so the agent
can't change it. Log in fresh there: a session saved by `globalSetup` may expire during a long run. Make it
safe to run twice, and end with a line like "Closed 4 of 4 test records"; the summary shows that line.

The credentials are environment variables for the hooks: `QA_USERNAME`, `QA_PASSWORD`, and for a second user
`QA_USERNAME_2`, `QA_PASSWORD_2`. The agent's tests import `test` and `expect` from the action's fixtures,
which is how `beforeEach.ts` and `afterEach.ts` reach every test; you don't need to do anything for that.

Tips for `instructions.md`, learned from the first runs:

- **Give exact locators for tricky flows**, such as a form with icons, comboboxes that load slowly or
  elements with the same text. Plain steps are enough for most pages, but for these the agent loses its
  attempts on guessing. A line like ``page.locator("div").filter({ hasText: /^person$/ }).click()`` is still
  markdown, and the agent copies it.
- **List the main pages with their paths.** It saves the agent many turns of searching.
- **Say where the UI labels are**, for example the translation file for the browser locale you test with.
- **Be honest about the rights of the test users.** If you don't know them exactly, say so. The agent then
  marks "users without right X" tickets as needs-human instead of reporting a false bug.
- **Mark test data clearly**, for example with a "QA Agent:" prefix, so `globalTeardown.ts` can find it and your
  team recognizes it.
- **Keep the agent creating little data**: say "one record per spec file, in `test.beforeAll`".
- **Wait for delays in `globalTeardown.ts`**, for example when a search index updates a few seconds later.
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
- no credentials on the runner when the action starts, and privileged steps after it in a separate job
  (see Security).

### 6. First run

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
| `language` | `English` | Language of the Slack message. With `Dutch`, the fixed texts are Dutch too. |
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
| `language` | `English` | Language of the fixed Slack texts, such as the report link: `Dutch` or `English`. Use the same value as in the main action. |

## Cost

Through Copilot, Claude Haiku 5.5 costs $0.10 per million input tokens and $0.50 per million output
tokens. A run on a busy day (15 PRs, 35 browser tests, about 30 minutes) used about 9 AI credits, which is
$0.09. Days without testable PRs cost nothing; the agent doesn't even start.

The job's timeout caps the cost. The action deliberately doesn't set Copilot's credit limit: with it, the
model kept telling itself the budget was tight and skipped tests, even far below the limit.

The job summary shows the credits and model calls of every run.

## Security

- **Credentials.** With a `globalSetup.ts` that saves sessions, only your hooks get the test users'
  passwords; the agent and its tests don't. Without it, the passwords are environment variables for the
  tests the agent writes, but the agent itself never sees their values. Use test users that only exist on
  the test environment. Jira
  credentials are only used before the agent starts, and the Slack webhook only exists in the separate
  report job. The workflow token is redacted from the agent's output.
- **Evidence.** Playwright traces and the HTML report would record the password the login fills in, so
  neither is produced. Before upload, the action replaces the test users' passwords with asterisks in every
  file of the evidence: test results, specs, the agent's transcripts and the cleanup log.
- **What the agent can do.** Read the repository, create and edit files, run its tests through
  `npm run`, and use the read-only shell commands Copilot CLI allows by default (`cat`, `ls`, `tail`).
  Commands that change or delete files, URL fetching and Copilot's built-in GitHub tools are off.
  Copilot CLI can't limit file writes to a folder, so:
  - the `.qa-agent/` files are restored from git before `globalTeardown.ts` runs;
  - the report runs on a fresh runner;
  - nothing in the agent's job pushes or deploys.
- **Your own privileged steps.** Tests the agent writes can run any program on its runner, and can change
  what later steps there run. So remove any credentials your setup steps leave on the runner before the
  action starts, and run privileged steps after the agent, such as undoing your setup, in a separate job.
- **Input.** PR descriptions and tickets reach the agent as input. The setup trusts the people who write
  them; don't run it on repositories that accept PRs from outsiders without review.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Model "…" from --model flag is not available` | The model isn't enabled in the organization's Copilot policies. |
| The run is green but Slack says it didn't finish | The agent didn't produce valid results; see `output/session.md` in the artifact. |
| "I couldn't log in or prepare the test environment" | `globalSetup.ts` failed; see `output/global-setup-log.txt` in the artifact. Without `globalSetup.ts`: describe the login more precisely in `instructions.md`. |
| `merge commit of #… not found` | The checkout is shallow; use `fetch-depth: 0`. |
| The agent marks most items "not tested" | Something in the instructions mentions cost or limits. Remove it. |
| The cleanup misses records | See `output/global-teardown-log.txt`; check how `globalTeardown.ts` finds them, and wait for delays such as a search index. |
| The agent's tests fail on labels | Tell it in `instructions.md` where the labels are and which locale the tests use. |

## Updating

Releases are tagged (`v1`, `v1.1.0`, …). Pin a commit SHA in your workflow, with the version as a comment,
and let Renovate or Dependabot propose updates.
