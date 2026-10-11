// A value under OK, or an error under ERROR, for callers that would rather
// branch than catch. From iara's src/utils/result.ts, trimmed to what
// bend-lint uses.

// Types
// =====

export type ErrorShape<
  T extends string = string,
  U extends Record<string, unknown> = Record<string, unknown>,
> = string | Error | { type: T; [ERROR_METADATA]?: U };

export type ResultOk<T> = Readonly<{ readonly [OK]: T }>;

export type ResultErr<E extends ErrorShape = ErrorShape> = Readonly<{ readonly [ERROR]: E }>;

export type Result<T, E extends ErrorShape = ErrorShape> = ResultOk<T> | ResultErr<E>;

// Constants
// =========

export const OK = "OK" as const;

export const ERROR = "ERROR" as const;

export const ERROR_METADATA = "ERROR_METADATA" as const;

// Functions
// =========

export const ok = <T>(value: T): ResultOk<T> => ({ [OK]: value });

export const error = <E extends ErrorShape>(value: E): ResultErr<E> => ({ [ERROR]: value });

// The value, or a throw: an Error as it is, a string as an Error's message,
// and a typed error as an Error with its metadata's message (else its
// type), caused by the typed error.
export const unwrap = <T, E extends ErrorShape>(res: Result<T, E>): T => {
  if (OK in res) {
    return res[OK];
  }
  const e = res[ERROR];
  if (e instanceof Error) {
    throw e;
  }
  if (typeof e === "string") {
    throw new Error(e);
  }
  const said = e[ERROR_METADATA]?.message;
  throw new Error(typeof said === "string" ? said : e.type, { cause: e });
};
