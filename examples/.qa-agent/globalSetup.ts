import { chromium, expect, type FullConfig, type Page } from "@playwright/test";

// Runs once before the agent starts. Here: log in each test user and save the session, so every test the
// agent writes starts logged in, and neither the agent nor its tests need the passwords.
// When this throws, the agent doesn't run and the report says it couldn't prepare the test environment.

const testUsers = [
  { session: "auth/user1.json", username: process.env.QA_USERNAME, password: process.env.QA_PASSWORD },
  { session: "auth/user2.json", username: process.env.QA_USERNAME_2, password: process.env.QA_PASSWORD_2 },
];

export async function login(page: Page, username: string, password: string) {
  await page.goto("/login");
  await page.getByLabel("Email").fill(username);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
}

export default async function globalSetup(config: FullConfig) {
  const { baseURL, locale } = config.projects[0].use;
  const browser = await chromium.launch();
  try {
    for (const { session, username, password } of testUsers) {
      if (!username || !password) continue;
      const page = await browser.newPage({ baseURL, locale });
      await login(page, username, password);
      await page.context().storageState({ path: session });
      await page.close();
    }
  } finally {
    await browser.close();
  }
}
