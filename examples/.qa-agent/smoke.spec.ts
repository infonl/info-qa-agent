import { test } from "@playwright/test";
import { login } from "./helpers";

// The agent runs this first. When it fails, the agent reports that it couldn't log in and tests nothing.
test("smoke: the customer logs in and sees the dashboard", async ({ page }) => {
  await login(page, "customer");
});
