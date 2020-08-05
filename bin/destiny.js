"use strict";

const { Destiny } = require("../lib");

(async () => {
  try {
    const d = new Destiny({ dir: "node_modules" });
    await d.update();
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
})();
