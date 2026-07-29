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
// The upstream entry also runs a once-per-24h auto-update check before
// parsing. That is skipped here so hooks stay fast and deterministic; run
// "ai-sync update" (or re-run install.ps1) to update the tool.
//
// Override the tool location with AI_SYNC_CLI if it is not in the default
// install path used by install.ps1.
import { homedir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const cliPath = process.env.AI_SYNC_CLI
    ?? path.join(homedir(), ".ai-sync-tools", "ai-sync", "dist", "cli.js");

const { program } = await import(pathToFileURL(cliPath).href);
await program.parseAsync();
