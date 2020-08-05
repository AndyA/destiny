"use strict";

const fs = require("fs");

async function forceLink(src, dst) {
  const tmp = dst + ".fsx.forceLink.tmp";
  await fs.promises.link(src, tmp);
  await fs.promises.rename(tmp, dst);
}

module.exports = { forceLink };
