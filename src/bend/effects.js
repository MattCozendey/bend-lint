// The effects of lint.bend. bend-lint puts its channel on
// globalThis.BEND_LINT before it runs a rule, and removes it after. Bool,
// String and U32 are native JS values here; other data is {$: CID(Name), ...}.

const LINT_SEVERITY = {
  [CID(Error)]: "error",
  [CID(Warning)]: "warning",
  [CID(Information)]: "information",
  [CID(Hint)]: "hint",
};
const LINT_QUANTITY = { erased: CID(Erased), once: CID(Once), many: CID(Many) };
const LINT_APPLICABILITY = {
  [CID(Safe)]: "safe",
  [CID(Suggested)]: "suggested",
  [CID(Dangerous)]: "dangerous",
};

function lint_host() {
  const host = globalThis.BEND_LINT;
  if (host === undefined) {
    throw new Error(
      "this program is a rule; run it with bun tools/bend-lint/src/lint.ts <file.bend> --rules <rule.bend>",
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

function lint_maybe(x) {
  return x === undefined ? { $: CID(None) } : { $: CID(Some), value: x };
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

function lint_fact(w) {
  return lint_maybe(
    w && {
      $: CID(Fact),
      node: lint_node(w.node),
      owner: w.owner,
      inst: w.inst,
      quantity: { $: LINT_QUANTITY[w.quantity] },
      term: lint_term(w.type),
      span: lint_maybe(w.span && lint_span(w.span)),
    },
  );
}

function lint_input() {
  const { sources, options } = lint_host().input();
  return {
    $: CID(Input),
    sources: lint_list(
      sources.map((s) => ({ $: CID(Source), path: s.path, text: s.text, root: s.root })),
    ),
    options: lint_list(
      Object.entries(options).map(([key, v]) => ({ $: CID(Option), key, value: lint_value(v) })),
    ),
  };
}

function lint_report(diags) {
  lint_host().report(
    lint_unlist(diags).map((d) => ({
      severity: LINT_SEVERITY[d.severity.$],
      message: d.message,
      span: d.span.$ === CID(Some) ? lint_spot(d.span.value) : undefined,
      fixes: lint_unlist(d.fixes).map((f) => ({
        title: f.title,
        applicability: LINT_APPLICABILITY[f.applicability.$],
        edits: lint_unlist(f.edits).map((e) => ({ span: lint_spot(e.span), text: e.text })),
      })),
    })),
  );
  return { $: CID(Unit) };
}

io_eff(CID(input), lint_input);
io_eff(CID(report), lint_report);
io_eff(CID(next_fact), () => lint_fact(lint_host().next()));
io_eff(CID(text), (span) => lint_host().text(lint_spot(span)));
io_eff(CID(body), (name) => {
  const id = lint_host().body(name);
  return lint_maybe(id === undefined ? undefined : lint_node(id));
});
io_eff(CID(shape), (n) => {
  const s = lint_host().shape(n.id);
  return {
    $: CID(Shape),
    kind: s.kind,
    name: s.name,
    span: lint_maybe(s.span && lint_span(s.span)),
    children: lint_list(s.children.map(lint_node)),
  };
});
io_eff(CID(nodes), (n) => lint_list(lint_host().nodes(n.id).map(lint_node)));
io_eff(CID(parent), (n) => {
  const id = lint_host().parent(n.id);
  return lint_maybe(id === undefined ? undefined : lint_node(id));
});
io_eff(CID(strip), (n) => lint_node(lint_host().strip(n.id)));
io_eff(CID(fact), (n) => lint_fact(lint_host().fact(n.id)));
io_eff(CID(binder), (f) => {
  const id = lint_host().binder(f.node.id);
  return lint_maybe(id === undefined ? undefined : lint_term(id));
});
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
