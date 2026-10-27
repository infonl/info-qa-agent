# About this application

<!-- Replace everything below. Keep it short and factual: the agent reads it at the start of every run. -->

ACME Portal is a web app where customers manage their orders. The UI is React, in English.

## Pages

| Path | What |
|---|---|
| `/` | Dashboard |
| `/orders`, `/orders/<id>` | Order list and detail |
| `/settings` | Account settings |

## Test users

| Helper name | What it can do |
|---|---|
| `customer` | A normal customer with a few orders |
| `admin` | Can open `/admin`, look but never save |

## Test data

- Create orders with `createOrder(page, { description })` from `helpers.ts`; the description gets the
  prefix "QA Agent", and the cleanup removes those orders after the run.
- Create as few orders as you can: one per spec file, in `test.beforeAll`.

## Project rules

- Never change data you didn't create in this run.
- Never send e-mail to a real address; use `@example.com`.
- The labels of the UI are in `src/locales/en.json`.
