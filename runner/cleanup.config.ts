import { defineConfig, devices } from "@playwright/test";
import os from "os";
import path from "path";

// A config of its own, so the cleanup never clears the screenshots and reports of the agent run.
export default defineConfig({
  testDir: "project",
  testMatch: "cleanup.spec.ts",
  outputDir: path.join(os.tmpdir(), "qa-agent-cleanup"),
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
