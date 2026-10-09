// The effects of lint.bend. bend-lint puts its channel on
// globalThis.BEND_LINT before it runs a rule, and removes it after. Bool,
// String and U32 are native JS values here; other data is {$: CID(Name), ...}.

// Each name's constructor, and back.
const LINT_SEVERITY = {
  error: CID(Error),
  warning: CID(Warning),
  information: CID(Information),
  hint: CID(Hint),
};
const LINT_QUANTITY = { erased: CID(Erased), once: CID(Once), many: CID(Many) };
const LINT_DECLARATION = {
  import: CID(Import),
  def: CID(Definition),
  type: CID(Datatype),
  constructor: CID(Constructor),
  parameter: CID(Parameter),
  variable: CID(Variable),
  field: CID(Field),
};
const LINT_APPLICABILITY = {
  safe: CID(Safe),
  suggested: CID(Suggested),
  dangerous: CID(Dangerous),
};
const LINT_NAMES = Object.fromEntries(
  [LINT_SEVERITY, LINT_APPLICABILITY].flatMap((m) => Object.entries(m).map(([n, c]) => [c, n])),
);

function lint_host() {
  const host = globalThis.BEND_LINT;
  if (host === undefined) {
    throw new Error(
      "this program is a rule; run it with bun src/lint.ts <file.bend> --rules <rule.bend>",
    );
  }
  return host;
}

function lint_list(xs) {
  return xs.reduceRight((tail, head) => ({ $: CID(Con), head, tail }), { $: CID(Nil) });
}

function lint_unlist(xs) {
  const out = [];
  for (; xs.$ === CID(Con); xs = xs.tail) {
    out.push(xs.head);
  }
  return out;
}

// x as a Maybe, its value made by f.
function lint_maybe(x, f = (y) => y) {
  return x === undefined ? { $: CID(None) } : { $: CID(Some), value: f(x) };
}

function lint_span(s) {
  return { $: CID(Span), path: s.path, beg: s.beg, end: s.end };
}

function lint_spot(s) {
  return { path: s.path, beg: s.beg, end: s.end };
}

function lint_value(v) {
  return typeof v === "number"
    ? { $: CID(Num), value: v }
    : typeof v === "boolean"
      ? { $: CID(Flag), value: v }
      : { $: CID(Text), value: v };
}

function lint_term(id) {
  return { $: CID(Term), id };
}

function lint_node(id) {
  return { $: CID(Node), id };
}

function lint_fact(wire) {
  return lint_maybe(wire, (w) => ({
    $: CID(Fact),
    node: lint_node(w.node),
    owner: w.owner,
    inst: w.inst,
    quantity: { $: LINT_QUANTITY[w.quantity] },
    term: lint_term(w.type),
    span: lint_maybe(w.span, lint_span),
  }));
}

function lint_source(s) {
  return { $: CID(Source), path: s.path, text: s.text, root: s.root };
}

// A finding as the host gives it, as a Lint.Diag.
function lint_diag(d) {
  return {
    $: CID(Diag),
    severity: { $: LINT_SEVERITY[d.severity] },
    message: d.message,
    span: lint_maybe(d.span, lint_span),
    fixes: lint_list(
      d.fixes.map((f) => ({
        $: CID(Fix),
        title: f.title,
        applicability: { $: LINT_APPLICABILITY[f.applicability] },
        edits: lint_list(
          f.edits.map((e) => ({ $: CID(Edit), span: lint_span(e.span), text: e.text })),
        ),
      })),
    ),
    about: lint_fact(d.about),
  };
}

function lint_input() {
  const { sources, options, prior } = lint_host().input();
  return {
    $: CID(Input),
    root: lint_source(sources.find((s) => s.root)),
    sources: lint_list(sources.map(lint_source)),
    options: lint_list(
      Object.entries(options).map(([key, v]) => ({ $: CID(Option), key, value: lint_value(v) })),
    ),
    prior: lint_list(prior.map((p) => ({ $: CID(Found), code: p.code, diag: lint_diag(p.diag) }))),
  };
}

function lint_report(diags) {
  lint_host().report(
    lint_unlist(diags).map((d) => ({
      severity: LINT_NAMES[d.severity.$],
      message: d.message,
      span: d.span.$ === CID(Some) ? lint_spot(d.span.value) : undefined,
      fixes: lint_unlist(d.fixes).map((f) => ({
        title: f.title,
        applicability: LINT_NAMES[f.applicability.$],
        edits: lint_unlist(f.edits).map((e) => ({ span: lint_spot(e.span), text: e.text })),
      })),
      about: d.about.$ === CID(Some) ? d.about.value.node.id : undefined,
    })),
  );
  return { $: CID(Unit) };
}

io_eff(CID(input), lint_input);
io_eff(CID(report), lint_report);
io_eff(CID(next_fact), () => lint_fact(lint_host().next()));
io_eff(CID(same_declarations), (text) => lint_host().sameDeclarations(text));
io_eff(CID(aborted), () => lint_host().aborted());
io_eff(CID(text), (span) => lint_host().text(lint_spot(span)));
io_eff(CID(declarations), () =>
  lint_list(
    lint_host()
      .declarations()
      .map((d) => ({
        $: CID(Declaration),
        kind: { $: LINT_DECLARATION[d.kind] },
        name: d.name,
        owner: lint_maybe(d.owner),
        span: lint_span(d.span),
        references: lint_list(
          d.references.map((r) => ({
            $: CID(Reference),
            owner: r.owner,
            span: lint_span(r.span),
          })),
        ),
      })),
  ),
);
io_eff(CID(body), (name) => lint_maybe(lint_host().body(name), lint_node));
io_eff(CID(shape), (n) => {
  const s = lint_host().shape(n.id);
  return {
    $: CID(Shape),
    kind: s.kind,
    name: s.name,
    span: lint_maybe(s.span, lint_span),
    children: lint_list(s.children.map(lint_node)),
  };
});
io_eff(CID(nodes), (n) => lint_list(lint_host().nodes(n.id).map(lint_node)));
io_eff(CID(parent), (n) => lint_maybe(lint_host().parent(n.id), lint_node));
io_eff(CID(strip), (n) => lint_node(lint_host().strip(n.id)));
io_eff(CID(fact), (n) => lint_fact(lint_host().fact(n.id)));
io_eff(CID(binder), (f) => lint_maybe(lint_host().binder(f.node.id), lint_term));
io_eff(CID(uses), (f) =>
  lint_list(
    lint_host()
      .uses(f.node.id)
      .map((u) => ({ $: CID(Use), name: u.name, quantity: { $: LINT_QUANTITY[u.quantity] } })),
  ),
);
io_eff(CID(same), (a, b) => lint_host().same(a.id, b.id));
io_eff(CID(show), (t) => lint_host().show(t.id));
io_eff(CID(normal), (t) => lint_term(lint_host().normal(t.id)));
