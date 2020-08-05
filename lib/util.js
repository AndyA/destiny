"use strict";

const inodeKey = o => [o.dev, o.ino].join("-");
const identKey = o => [o.hash, o.uid, o.gid, o.mode].join("-");
const identDevKey = o => [o.dev, identKey(o)].join("-");

module.exports = { inodeKey, identKey, identDevKey };
