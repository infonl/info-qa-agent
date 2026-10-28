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
  reporter: [
    ["line"],
    ["json", { outputFile: "output/playwright-results.json" }],
    ["html", { outputFolder: "output/playwright-report", open: "never" }],
  ],
  use: {
    baseURL: process.env.QA_APP_URL,
    locale: process.env.QA_LOCALE || "en-US",
    screenshot: "on",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
