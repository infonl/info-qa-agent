import { expect, test as base } from "@playwright/test";
import fs from "fs";
import path from "path";

// Every test the agent writes imports test and expect from here, so the project's beforeEach.ts and
// afterEach.ts run around each of them. Both take ({ page }, testInfo), like Playwright's own hooks.
const hookFile = (name: string) => path.join(__dirname, "project", `${name}.ts`);

async function runHook(name: string, page: unknown, testInfo: unknown) {
  if (!fs.existsSync(hookFile(name))) return;
  const module = await import(hookFile(name));
  // Playwright compiles TypeScript to CommonJS, so a default export can arrive one level deeper.
  const run = [module.default?.default, module.default, module[name]].find((candidate) => typeof candidate === "function");
  if (run) await run({ page }, testInfo);
}

export const test = base.extend<{ projectHooks: void }>({
  projectHooks: [
    async ({ page }, use, testInfo) => {
      await runHook("beforeEach", page, testInfo);
      await use();
      await runHook("afterEach", page, testInfo);
    },
    { auto: true },
  ],
});

export { expect };
