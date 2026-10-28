# QA agent: cleanup

A QA run just tested the application and may have created test data. Your only job is to write a script
that removes or closes that test data, following `project/cleanup.md`. Don't test anything.

## How

1. Read `project/cleanup.md`, and the other project files when it refers to them.
2. Write the cleanup as one Playwright test in `cleanup/cleanup.spec.ts`. It may use the browser or the
   application's API through `page.request` after logging in. To log in, reuse `tests/login.ts` when it
   exists (`import { login } from "../tests/login";`); otherwise follow the login instructions of the
   project. Credentials are in `QA_USERNAME` and `QA_PASSWORD`; never print them.
3. Make the script safe to run more than once: it only touches records that are still there.
4. Log each record it removes or closes, and at the end one line like "Closed 4 of 4 test records, 0 left."
5. Try it with `npm run cleanup` and fix a mistake at most twice. The script is run again after you anyway.

## Rules

- Only touch the test data `project/cleanup.md` describes. When in doubt, leave a record alone.
- Only open pages of the application under test.
- Only write files in `cleanup/` and `output/`.
