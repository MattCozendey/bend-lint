// Imports
// =======

import type { Plugin } from "@oxlint/plugins";

import { NO_TYPE_SYNONYMS } from "./no-type-synonyms.ts";

// Constants
// =========

const PLUGIN: Plugin = {
  meta: { name: "custom-oxlint-plugins" },
  rules: { "no-type-synonyms": NO_TYPE_SYNONYMS },
};

export default PLUGIN;
