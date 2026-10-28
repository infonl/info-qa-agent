import { defineConfig, devices } from "@playwright/test";

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
    screenshot: "on",
    trace: "off",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
