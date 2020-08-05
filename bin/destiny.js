#!/usr/bin/env node
"use strict";

const yargs = require("yargs");

const argv = yargs
  .command(require("../cmd/update"))
  .command(require("../cmd/link"))
  .alias("n", "dry-run")
  .describe("n", "Don't change anything")
  .boolean("n")
  .demandCommand()
  .help("h")
  .alias("h", "help").argv;
