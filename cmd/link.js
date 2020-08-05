"use strict";

const _ = require("lodash");
const { forceLink } = require("../lib/fsx");
const { Destiny } = require("../lib");

module.exports = {
  command: "link [dirs...]",
  describe: "Link duplicate files",

  builder: yargs => {
    yargs.positional("dirs", {
      describe: "Directories to visit",
      type: "string",
      default: "."
    });
  },

  handler: async argv => {
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
};
