"use strict";

const fs = require("fs");
const crypto = require("crypto");
const { inodeKey } = require("./util");

class DestinyHasher {
  constructor() {
    this.cache = {};
  }

  async hashFile(file) {
    return new Promise((resolve, reject) => {
      const hash = crypto.createHash("md5");
      hash.setEncoding("hex");
      const fd = fs
        .createReadStream(file)
        .on("end", () => {
          hash.end();
          resolve(hash.read());
        })
        .on("error", e => reject(e))
        .pipe(hash);
    });
  }

  hashObject(obj) {
    const { cache, worker } = this;
    const key = inodeKey(obj);
    return (cache[key] = cache[key] || this.hashFile(obj.name));
  }

  flush() {}
}

module.exports = DestinyHasher;
