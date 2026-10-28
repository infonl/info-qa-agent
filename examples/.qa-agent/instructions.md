# About this application

<!-- Replace everything below. Keep it short and factual: the agent reads it at the start of every run. -->

ACME Portal is a web app where customers manage their orders. The UI is React, in English. The labels are
in `src/locales/en.json`.

## Test users

`globalSetup.ts` logs them in before the run, so tests start logged in as user 1.

- User 1 (`auth/user1.json`, the default) is a normal customer with a few orders.
- User 2 (`auth/user2.json`) is an admin: it can open `/admin`, but never save anything there.

## Pages

| Path | What |
|---|---|
| `/` | Dashboard |
| `/orders`, `/orders/<id>` | Order list and detail |
| `/orders/new` | Create an order |
| `/settings` | Account settings |

## Test data

- Create orders at `/orders/new`. Always start the description with "QA Agent:": `globalTeardown.ts`
  deletes those orders after the run, so don't delete them yourself.
- Create as few orders as you can: one per spec file, in `test.beforeAll`.

## Project rules

- Never change data you didn't create in this run.
- Never send e-mail to a real address; use `@example.com`.
