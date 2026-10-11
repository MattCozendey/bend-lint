import type { RuleTester } from "oxlint/plugins-dev";

export default {
  meta: { name: "bend-lint" },
  rules: {
    "no-type-synonyms": {
      meta: {
        type: "suggestion",
        schema: [],
        messages: { synonym: "Use the original type directly instead of renaming it." },
      },
      create: (context) => ({
        TSTypeAliasDeclaration: (node) => {
          if (
            node.typeAnnotation.type === "TSTypeReference" &&
            !node.typeAnnotation.typeArguments
          ) {
            context.report({ node, messageId: "synonym" });
          }
        },
      }),
    } satisfies Parameters<RuleTester["run"]>[1],
  },
};
