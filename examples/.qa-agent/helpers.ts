import { expect, Page } from "@playwright/test";

// The agent always logs in through these helpers, so credentials never end up in its tests.
// Read the credentials from the environment variables your workflow passes to the action.

export type TestUser = "customer" | "admin";

const credentials: Record<TestUser, { username?: string; password?: string }> = {
  customer: {
    username: process.env.QA_USER_USERNAME,
    password: process.env.QA_USER_PASSWORD,
  },
  admin: {
    username: process.env.QA_ADMIN_USERNAME,
    password: process.env.QA_ADMIN_PASSWORD,
  },
};

export async function login(page: Page, user: TestUser = "customer") {
  const { username, password } = credentials[user];
  if (!username || !password) {
    throw new Error(`No credentials for test user '${user}' in the environment`);
  }
  await page.goto("/login");
  await page.getByLabel("Email").fill(username);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
}

export async function createOrder(page: Page, { description }: { description: string }) {
  await page.goto("/orders/new");
  await page.getByLabel("Description").fill(`QA Agent: ${description}`);
  await page.getByRole("button", { name: "Create" }).click();
  await page.waitForURL(/\/orders\/\d+/);
  return page.url().split("/").pop();
}
