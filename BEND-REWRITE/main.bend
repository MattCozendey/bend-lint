# ALL LOGIC OF THE REWRITE WILL EXIST ONLY HERE FOR NOW INCLUDING LAWS AND PROOFS IF ANY.
# THIS FILE MUST RUN THROUGH BEND-LINT (THE TS VERSION) - ALL RULES.
# I DECIDED WE WILL DROP "SUGGESTED". REPORTING IS MORE IMPORTANT THAN AUTOFXING FOR AGENTS.
# WE WILL PROVIDE FIXES WHEN WE HAVE THEM.
# ANOTHER DRIFT: EDITS ARE NOT ONLY AN ARRAY OF CHANGES TO A FILE OR FILES, BUT ALSO
# FILE RENAMES, OR FILE DELETIONS.
# THIS FILE MUST BE SELF CONTAINED.
import Base

type FixLevel is Data:
  NoFix{}
  AutoFix{}
  DangerousFix{}

# A file: its path and its text. A path is ALWAYS a normalized POSIX path.
type Source is Data:
  Source{path: String, text: String}

# path: as in Source. Offsets count characters (code points) from the
# start of the file.
type Span is Data:
  Span{path: String, beg: U32, end: U32}

type Severity is Data:
  Error{}
  Warning{}
  Information{}
  Hint{}

type Diag is Data:
  Diag{severity: Severity, message: String, span: Span}

# id: namespace/name, the code of its findings.
type Rule is Type:
  Rule{id: String, run: Source -> List<&2, Diag>}
