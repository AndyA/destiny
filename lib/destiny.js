"use strict";

const _ = require("lodash");
const os = require("os");
const fs = require("fs");
const path = require("path");
const lazyProps = require("./lazyprops");
const DestinyManifest = require("./manifest");
const DestinyHasher = require("./hasher");

const Destiny = lazyProps(
  class {
    constructor(opt) {
      this.opt = Object.assign(
        {
          manifest: "MANIFEST.json",
          dir: ".",
          ignoreHidden: true,
          followLinks: false,
          log: console.log.bind(console)
        },
        opt || {}
      );
    }

    log(...args) {
      this.opt.log(...args);
    }

    async readObject(name) {
      const { opt } = this;
      try {
        const stat = await (opt.followLinks
          ? fs.promises.stat(name)
          : fs.promises.lstat(name));

        const rec = {
          name,
          mtime: stat.mtimeMs / 1000,
          ..._.pick(stat, "dev", "gid", "ino", "mode", "size", "uid")
        };

        if (stat.isFile()) return { ...rec, kind: "file" };
        if (stat.isDirectory()) return { ...rec, kind: "directory" };

        if (stat.isSymbolicLink()) {
          const link = await fs.promises.readlink(name);
          return { ...rec, link, kind: "link" };
        }

        if (stat.isFIFO()) return { ...rec, kind: "fifo" };
        if (stat.isSocket()) return { ...rec, kind: "socket" };

        if (stat.isBlockDevice() || stat.isCharacterDevice())
          return { ...rec, rdev: stat.rdev, kind: "device" };

        return { ...rec, kind: "unknown" };
      } catch (e) {
        if (!e.syscall) throw e;
        return { name, error: e.code, kind: "error" };
      }
    }

    async readDir(dir) {
      const { opt } = this;

      const getNames = async () => {
        const names = await fs.promises.readdir(dir);
        if (!opt.ignoreHidden) return names;
        return names.filter(name => name[0] !== ".");
      };

      const names = (await getNames(dir))
        .sort()
        .map(name => path.join(dir, name));

      return Promise.all(names.map(name => this.readObject(name)));
    }

    async update() {
      await (await this.manifest).saveManifest();
    }
  },
  {
    manifestFile: function() {
      const { opt } = this;
      return path.join(opt.dir, opt.manifest);
    },

    current: function() {
      return DestinyManifest.loadManifest(this.manifestFile, this.opt, {
        meta: {},
        object: []
      });
    },

    manifest: async function() {
      const { opt, manifestFile } = this;
      const queue = [opt.dir];

      const meta = {
        host: os.hostname().replace(/\..*/, ""),
        root: path.resolve(opt.dir),
        time: new Date() / 1000,
        manifest: path.resolve(manifestFile),
        version: 2
      };

      const object = [];

      const current = await this.current;

      const hasher = new DestinyHasher();

      while (queue.length) {
        const dir = queue.pop();
        this.log(`Scanning ${dir}`);

        const objs = await this.readDir(dir);

        const dirs = objs.filter(o => o.kind === "directory").map(d => d.name);
        queue.push(..._.reverse(dirs));

        for (const obj of objs) {
          if (obj.name === manifestFile) continue;
          if (obj.kind === "file") {
            const prev = current.findLike(obj);
            if (prev) {
              obj.hash = prev.hash;
            } else {
              obj.hash = await hasher.hashObject(obj);
              this.log(`${obj.hash} ${obj.name}`);
            }
          }
          object.push(obj);
        }
      }

      return new DestinyManifest({ meta, object }, manifestFile, this.opt);
    }
  }
);

module.exports = Destiny;
