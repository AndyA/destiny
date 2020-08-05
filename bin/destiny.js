#!/usr/bin/env node
"use strict";

const { Destiny } = require("../lib");
const yargs = require("yargs");

const argv = yargs
  .command(
    "update [dirs...]",
    "Update manifest",
    yargs => {
      yargs.positional("dirs", {
        describe: "Directories to scan",
        type: "string",
        default: "."
      });
    },
    async argv => {
      for (const dir of argv.dirs) {
        const d = new Destiny({ dir });
        await d.update();
      }
    }
  )
  .demandCommand().argv;
