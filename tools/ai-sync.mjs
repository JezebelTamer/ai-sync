#!/usr/bin/env node
// Windows-safe launcher for the ai-sync CLI.
//
// dist/cli.js only self-executes when process.argv[1] ends with "/cli/index.ts",
// "/cli.js", or "/ai-sync" (forward slashes). On Windows, argv[1] is a
// backslash path, so none of those match and every direct invocation of
// dist/cli.js parses nothing: silent no-op, exit 0. This wrapper imports the
// CLI's exported commander program and parses explicitly, which works on any
// platform.
//
// Never expose this wrapper through a shim or symlink named plain "ai-sync":
// if argv[1] ever ends with "/ai-sync" the import itself triggers the
// upstream self-run block and the command executes twice.
//
// The upstream entry also runs a once-per-24h auto-update check before
// parsing. That is skipped here so hooks stay fast and deterministic; run
// "ai-sync update" (or re-run install.ps1) to update the tool.
//
// Override the tool location with AI_SYNC_CLI if it is not in the default
// install path used by install.ps1.
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const cliPath = process.env.AI_SYNC_CLI
    || path.join(homedir(), ".ai-sync-tools", "ai-sync", "dist", "cli.js");

if (!existsSync(cliPath)) {
    console.error(`ai-sync CLI not found at ${cliPath}; run install.ps1 or set AI_SYNC_CLI`);
    process.exit(1);
}

// Force --skip-discovery onto every push (hooks, /sync skill, manual):
// upstream tool discovery auto-migrates the sync repo to a v3 layout that
// its own push/pull branches cannot read yet (they test version === 2),
// which would silently break sync on every machine. Remove once upstream
// handles v3.
if (process.argv.includes("push") && !process.argv.includes("--skip-discovery")) {
    process.argv.push("--skip-discovery");
}

const { program } = await import(pathToFileURL(cliPath).href);
await program.parseAsync();
