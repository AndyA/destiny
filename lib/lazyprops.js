"use strict";

module.exports = (() => {
  const privates = new WeakMap();
  return (clazz, attr) => {
    for (const [name, vf] of Object.entries(attr))
      Object.defineProperty(clazz.prototype, name, {
        get: function() {
          let me = privates.get(this);
          if (!me) privates.set(this, (me = new Map()));
          if (me.has(name)) return me.get(name);
          const val = vf.call(this, name);
          me.set(name, val);
          return val;
        }
      });
    return clazz;
  };
})();
