"use strict";

const _ = require("lodash");
const fs = require("fs");

const { inodeKey, identKey, identDevKey } = require("./util");
const lazyProps = require("./lazyprops");

const makeGrouper = key =>
  function() {
    return _.groupBy(
      (this.manifest.object || []).filter(obj => obj.hash),
      key
    );
  };

const DestinyManifest = lazyProps(
  class {
    constructor(obj, name, opt) {
      this.obj = obj;
      this.name = name;
      this.opt = Object.assign({}, opt || {});
    }

    static async loadJSON(file, fallback) {
      try {
        let data = await fs.promises.readFile(file, "utf8");

        // Remove trailing nul that destiny seems to be writing
        if (data[data.length - 1] === "\0")
          data = data.substr(0, data.length - 1);

        return JSON.parse(data);
      } catch (e) {
        if (fallback && e.code === "ENOENT") return fallback;
        throw e;
      }
    }

    static async saveJSON(file, data) {
      const tmp = file + ".tmp";
      await fs.promises.writeFile(tmp, JSON.stringify(data));
      await fs.promises.rename(tmp, file);
    }

    static async loadManifest(name, opt, fallback) {
      const obj = await this.loadJSON(name, fallback);
      return new this(obj, name, opt);
    }

    async saveManifest() {
      await this.constructor.saveJSON(this.name, this.manifest);
    }

    findLike(rec) {
      const nearEnough = (prev, rec) =>
        prev &&
        prev.size === rec.size &&
        Math.floor(prev.mtime) === Math.floor(rec.mtime);

      const bn = this.byName[rec.name];
      if (nearEnough(bn, rec)) return bn;
      const bi = this.byInode[inodeKey(rec)];
      if (nearEnough(bi, rec)) return bi;
    }
  },
  {
    manifest: function() {
      const { obj } = this;

      const version = (obj.meta.version = obj.meta.version || 1);

      if (version < 2) {
        obj.meta.version = 2;
        obj.object = obj.object.map(o => {
          const { hash, name, link, mode, ...rest } = o;
          return {
            hash,
            name,
            link,
            mode: parseInt(mode, 8),
            ..._.mapValues(rest, parseInt)
          };
        });
      }

      return obj;
    },

    byName: function() {
      return _.keyBy(this.manifest.object || [], "name");
    },

    byInode: function() {
      return _.keyBy(this.manifest.object || [], inodeKey);
    },

    byHash: makeGrouper("hash"),
    byIdent: makeGrouper(identKey),
    byIdentDev: makeGrouper(identDevKey),

    duplicates: function() {
      const dupSets = Object.values(this.byIdent).map(objs =>
        Object.values(_.groupBy(objs, inodeKey)).sort(
          (a, b) => b.length - a.length
        )
      );
      return dupSets.filter(s => s.length > 1);
    }
  }
);

module.exports = DestinyManifest;
