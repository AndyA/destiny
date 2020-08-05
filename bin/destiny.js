#!/usr/bin/env node
"use strict";

const _ = require("lodash");
const yargs = require("yargs");
const fs = require("fs");
const { forceLink } = require("../lib/fsx");
const { Destiny } = require("../lib");

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
      if (argv.n) return console.error(`Can't dry run update`);
      for (const dir of argv.dirs) {
        const d = new Destiny({ dir });
        await d.update();
      }
    }
  )
  .command(
    "link [dirs...]",
    "Link duplicate files",
    yargs => {
      yargs.positional("dirs", {
        describe: "Directories to visit",
        type: "string",
        default: "."
      });
    },
    async argv => {
      for (const dir of argv.dirs) {
        const d = new Destiny({ dir });
        const current = await d.current;

        for (const set of current.duplicates) {
          d.log(`Linking ${set[0][0].hash}`);
          const [[target], ...others] = set;
          for (const obj of _.flatten(others)) {
            d.log(`  ${target.name} -> ${obj.name}`);
            if (!argv.n) await forceLink(target.name, obj.name);
          }
        }
      }
    }
  )
  .alias("n", "dry-run")
  .describe("n", "Don't change anything")
  .boolean("n")
  .demandCommand()
  .help("h")
  .alias("h", "help").argv;
