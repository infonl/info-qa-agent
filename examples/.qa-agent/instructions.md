# About this application

<!-- Replace everything below. Keep it short and factual: the agent reads it at the start of every run. -->

ACME Portal is a web app where customers manage their orders. The UI is React, in English. The labels are
in `src/locales/en.json`.

## Logging in

- Open `/login`, fill "Email" and "Password", click "Sign in". The dashboard shows afterwards.
- `QA_USERNAME` is a normal customer with a few orders. `QA_USERNAME_2` is an admin: it can open `/admin`,
  but never save anything there.

## Pages

| Path | What |
|---|---|
| `/` | Dashboard |
| `/orders`, `/orders/<id>` | Order list and detail |
| `/orders/new` | Create an order |
| `/settings` | Account settings |

## Test data

- Create orders at `/orders/new`. Always start the description with "QA Agent:", so the cleanup finds them.
- Create as few orders as you can: one per spec file, in `test.beforeAll`.

## Project rules

- Never change data you didn't create in this run.
- Never send e-mail to a real address; use `@example.com`.
