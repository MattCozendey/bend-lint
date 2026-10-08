import { resolve, relative } from "node:path";
import { API, DiagnosticCategory } from "typescript/unstable/async";

const root = resolve(import.meta.dir, "..");
const config = resolve(root, "tsconfig.json");
const api = new API({ cwd: root });

try {
  const snapshot = await api.updateSnapshot({ openProjects: [config] });
  const project = snapshot.getProject(config);
  if (!project) throw new Error("TypeScript did not load " + config);
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
    const location = file ? relative(root, file) + ":" + diagnostic.pos : "tsconfig.json";
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
