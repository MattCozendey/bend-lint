// Type-checks this repo, as tsconfig.json says, with TypeScript's API: prints each diagnostic,
// and fails if one is an error.

// Imports
// =======

import { relative, resolve } from "node:path";

import { API, DiagnosticCategory } from "typescript/unstable/async";

// Constants
// =========

const ROOT = resolve(import.meta.dir, "..", "..");
const CONFIG = resolve(ROOT, "tsconfig.json");

// Side effects
// ============

const api = new API({ cwd: ROOT });

try {
  const snapshot = await api.updateSnapshot({ openProjects: [CONFIG] });
  const project = snapshot.getProject(CONFIG);
  if (!project) throw new Error("TypeScript did not load " + CONFIG);
  const program = project.program;
  const diagnostics = [
    ...(await program.getConfigFileParsingDiagnostics()),
    ...(await program.getProgramDiagnostics()),
    ...(await program.getGlobalDiagnostics()),
    ...(
      await Promise.all(
        project.rootFiles.map(async (file) => [
          ...(await program.getSyntacticDiagnostics(file)),
          ...(await program.getBindDiagnostics(file)),
          ...(await program.getSemanticDiagnostics(file)),
        ]),
      )
    ).flat(),
  ];
  for (const diagnostic of diagnostics) {
    const file = diagnostic.fileName;
    const location = file ? relative(ROOT, file) + ":" + diagnostic.pos : "tsconfig.json";
    console.error(location + ": TS" + diagnostic.code + ": " + diagnostic.text);
  }
  process.exitCode = diagnostics.some(
    (diagnostic) => diagnostic.category === DiagnosticCategory.Error,
  )
    ? 1
    : 0;
} finally {
  await api.close();
}
