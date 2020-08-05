"use strict";

const { Destiny } = require("../lib");

module.exports = {
  command: "update [dirs...]",
  describe: "Update manifest",

  builder: yargs => {
    yargs.positional("dirs", {
      describe: "Directories to scan",
      type: "string",
      default: "."
    });
  },

  handler: async argv => {
    if (argv.n) return console.error(`Can't dry run update`);
    for (const dir of argv.dirs) {
      const d = new Destiny({ dir });
      await d.update();
    }
  }
};
