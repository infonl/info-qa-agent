import { defineConfig, devices } from "@playwright/test";
import fs from "fs";

// When the project's globalSetup.ts saved a session for user 1, every test starts logged in with it.
const user1Session = "auth/user1.json";

export default defineConfig({
  testDir: ".",
  testMatch: ["tests/**/*.spec.ts"],
  outputDir: "output/test-results",
  timeout: 90_000,
  expect: { timeout: 15_000 },
  // One retry tells flaky from broken; more retries would hide real bugs.
  retries: 1,
  workers: 1,
  // No HTML report and no traces: both record the password the login fills in, the HTML report even in a
  // form that can't be scrubbed. The JSON results and screenshots are scrubbed before upload.
  reporter: [["line"], ["json", { outputFile: "output/playwright-results.json" }]],
  use: {
    baseURL: process.env.QA_APP_URL,
    locale: process.env.QA_LOCALE || "en-US",
    storageState: fs.existsSync(user1Session) ? user1Session : undefined,
    screenshot: "on",
    trace: "off",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
