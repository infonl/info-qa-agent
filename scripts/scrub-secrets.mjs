// Replaces the values of the given environment variables with asterisks of the same length in every file
// under the given directories, before the evidence is uploaded. Same length, so binary files stay valid.
//
// Usage: node scrub-secrets.mjs <directory>... (secrets from QA_PASSWORD and QA_PASSWORD_2)
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "fs";
import path from "path";

const secrets = ["QA_PASSWORD", "QA_PASSWORD_2"]
  .map((name) => process.env[name])
  .filter((value) => value && value.length >= 4)
  .map((value) => Buffer.from(value));

function* files(directory) {
  for (const entry of readdirSync(directory)) {
    if (entry === "node_modules") continue;
    const file = path.join(directory, entry);
    if (statSync(file).isDirectory()) yield* files(file);
    else yield file;
  }
}

let scrubbed = 0;
for (const directory of process.argv.slice(2).filter((directory) => existsSync(directory))) {
  for (const file of files(directory)) {
    const content = readFileSync(file);
    let changed = false;
    for (const secret of secrets) {
      for (let index = content.indexOf(secret); index !== -1; index = content.indexOf(secret, index)) {
        content.fill("*", index, index + secret.length);
        changed = true;
      }
    }
    if (changed) {
      writeFileSync(file, content);
      scrubbed++;
    }
  }
}
console.log(`Removed credentials from ${scrubbed} file(s).`);
