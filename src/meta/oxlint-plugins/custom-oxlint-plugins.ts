import type { Plugin } from "@oxlint/plugins";

import { noTypeSynonyms } from "./no-type-synonyms.ts";

const plugin: Plugin = {
  meta: { name: "custom-oxlint-plugins" },
  rules: { "no-type-synonyms": noTypeSynonyms },
};

export default plugin;
