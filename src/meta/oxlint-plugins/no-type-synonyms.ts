import { defineRule } from "@oxlint/plugins";
import type { Rule } from "@oxlint/plugins";

export const noTypeSynonyms: Rule = defineRule({
  meta: {
    type: "suggestion",
    schema: [],
    messages: { synonym: "Use the original type directly instead of renaming it." },
  },
  create: (context) => ({
    TSTypeAliasDeclaration: (node) => {
      if (node.typeAnnotation.type === "TSTypeReference" && !node.typeAnnotation.typeArguments) {
        context.report({ node, messageId: "synonym" });
      }
    },
  }),
});
