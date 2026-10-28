import { expect, type Page, type TestInfo } from "@playwright/test";

// Runs after every test the agent writes, with the same arguments as Playwright's test.afterEach.
// Here: fail a test when the application shows an unexpected error dialog, even if its own checks passed.

export default async function afterEach({ page }: { page: Page }, testInfo: TestInfo) {
  if (testInfo.status !== "passed") return;
  await expect(page.getByRole("alertdialog", { name: /something went wrong/i })).toBeHidden();
}
