import { chromium, type FullConfig } from "@playwright/test";
import { login } from "./globalSetup";

// Runs once after the agent, also when it crashed. Here: delete the orders the agent created, recognised by
// the "QA Agent:" prefix that instructions.md tells it to use. Log in fresh: a session saved by globalSetup
// may have expired during a long run.

export default async function globalTeardown(config: FullConfig) {
  const { baseURL, locale } = config.projects[0].use;
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ baseURL, locale });
    await login(page, process.env.QA_USERNAME!, process.env.QA_PASSWORD!);
    const orders = (await (await page.request.get("/api/orders?search=QA%20Agent:")).json()) as {
      id: string;
      description: string;
    }[];
    const testOrders = orders.filter(({ description }) => description.startsWith("QA Agent:"));
    for (const order of testOrders) {
      const response = await page.request.delete(`/api/orders/${order.id}`);
      console.log(`${order.id}: ${response.ok() ? "deleted" : `not deleted, HTTP ${response.status()}`}`);
    }
    console.log(`Closed ${testOrders.length} test records.`);
  } finally {
    await browser.close();
  }
}
