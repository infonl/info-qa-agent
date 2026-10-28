import { defineConfig, devices } from "@playwright/test";
import os from "os";
import path from "path";

// Runs globalSetup.ts and globalTeardown.ts of the project, outside the agent's test results.
export default defineConfig({
  testDir: "lifecycle",
  testMatch: "hook.spec.ts",
  outputDir: path.join(os.tmpdir(), "qa-agent-lifecycle"),
  timeout: 10 * 60_000,
  retries: 0,
  workers: 1,
  reporter: [["line"]],
  use: {
    baseURL: process.env.QA_APP_URL,
    locale: process.env.QA_LOCALE || "en-US",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
