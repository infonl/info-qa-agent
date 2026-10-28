import { test } from "@playwright/test";
import fs from "fs";
import path from "path";

// Runs the project's globalSetup.ts or globalTeardown.ts (chosen with QA_HOOK) once, with Playwright's
// signature: a default export that takes the config. The action runs them before and after the agent.
const hook = process.env.QA_HOOK ?? "";
const file = path.join(__dirname, "..", "project", `${hook}.ts`);

test(hook || "no hook", async ({}, testInfo) => {
  test.skip(!["globalSetup", "globalTeardown"].includes(hook) || !fs.existsSync(file), `No ${hook}.ts`);
  const module = await import(file);
  // Playwright compiles TypeScript to CommonJS, so a default export can arrive one level deeper.
  const run = [module.default?.default, module.default, module[hook]].find((candidate) => typeof candidate === "function");
  if (typeof run !== "function") throw new Error(`${hook}.ts has no default export function`);
  await run(testInfo.config);
});
