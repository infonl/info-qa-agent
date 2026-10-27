import { expect, test } from "@playwright/test";
import { login } from "./helpers";

// Optional. Runs after the agent, from the version in git, so the agent can't change it.
// Remove everything the agent created; here: the orders whose description starts with "QA Agent:".
test("remove the orders created by the QA agent", async ({ page }) => {
  await login(page, "customer");
  const response = await page.request.get("/api/orders?search=QA%20Agent:");
  expect(response.ok()).toBeTruthy();
  const orders = (await response.json()) as { id: string; description: string }[];
  for (const order of orders.filter(({ description }) => description.startsWith("QA Agent:"))) {
    const deleted = await page.request.delete(`/api/orders/${order.id}`);
    console.log(`${order.id}: ${deleted.ok() ? "removed" : `not removed, HTTP ${deleted.status()}`}`);
  }
});
