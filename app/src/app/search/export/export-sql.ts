/**
 * The statistical-unit export as ONE SQL statement (STATBUS-421 Phase 2).
 *
 * The export route runs `COPY (<select>) TO STDOUT WITH (FORMAT CSV, HEADER)`
 * as the user's own role (auth.jwt_switch_role on the statbus cookie), so the
 * export is a constant-memory stream with no aggregate and no 1 GiB ceiling.
 * This module turns the search page's PostgREST-style query parameters into
 * that statement.
 *
 * WHY A WHITELIST TRANSLATOR. COPY cannot take bind parameters, so every value
 * is inlined as an escaped SQL literal and every key is matched against a
 * fixed set of columns and operators. Anything not recognised is REJECTED with
 * an ExportQueryError (HTTP 400), never passed through: an unknown filter that
 * was silently ignored would export more rows than the user asked for.
 *
 * The semantics deliberately mirror what PostgREST did for the same parameters,
 * so the exported rows are the rows the search page shows:
 *   in.(a,b)      col = ANY('{a,b}')            (untyped array literal)
 *   eq/neq/gt/gte/lt/lte  col <op> 'v'          (untyped literal)
 *   like.a*b      col LIKE 'a%b'                (`*` is PostgREST's wildcard)
 *   is.null|true|false|unknown
 *   cd.path       col <@ 'path'                 (ltree "contained in")
 *   ov.{1,2}      col && '{1,2}'                (array overlap)
 *   fts(simple).q search @@ to_tsquery('simple', 'q')
 * Keys may be a plain column, `external_idents->>code` or
 * `stats_summary->code->sum`. The jsonb forms compare as jsonb (`->`) or text
 * (`->>`) exactly like PostgREST.
 *
 * COLUMN ORDER is explicit here: external identifiers, the shared columns in
 * their historical order (each *_name directly after its *_code), then the
 * statistical variables. The three names come from the SETOF computed
 * relationships through LEFT JOIN LATERAL, so a unit without a category or a
 * region keeps its row with an empty name (the arrow form in a select list is
 * what silently dropped 29,470 rows in Phase 1).
 */

export class ExportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ExportQueryError";
  }
}

/**
 * Response header carrying the exact row count of the export, counted in the
 * same snapshot as the COPY: the client's completeness reference.
 */
export const EXPORT_TOTAL_ROWS_HEADER = "X-Export-Total-Rows";

/** The configured columns that vary per installation. */
export interface ExportColumnConfig {
  /** Enabled external identifier type codes, in display order. */
  externalIdentCodes: ReadonlyArray<string>;
  /** Enabled statistical variable codes, in display order. */
  statCodes: ReadonlyArray<string>;
}

export interface ExportSql {
  /** The export SELECT (for COPY (...) TO STDOUT). */
  selectSql: string;
  /** SELECT count(*) over the same filter, for the announced total. */
  countSql: string;
  /** Output column names in order: the CSV header. */
  fieldNames: string[];
}

/** Params that shape pagination or response format and never filter rows. */
const IGNORED_PARAMS = new Set(["limit", "offset", "select", "format"]);

/**
 * statistical_unit columns usable in filters and ordering, by kind. The kind
 * decides which operators are meaningful; values stay untyped literals so
 * PostgreSQL resolves them against the column type exactly as PostgREST did.
 */
const SCALAR_COLUMNS = new Set([
  "unit_type",
  "unit_id",
  "valid_from",
  "valid_to",
  "valid_until",
  "name",
  "birth_date",
  "death_date",
  "primary_activity_category_id",
  "primary_activity_category_code",
  "secondary_activity_category_id",
  "secondary_activity_category_code",
  "sector_id",
  "sector_code",
  "sector_name",
  "legal_form_id",
  "legal_form_code",
  "legal_form_name",
  "physical_address_part1",
  "physical_address_part2",
  "physical_address_part3",
  "physical_postcode",
  "physical_postplace",
  "physical_region_id",
  "physical_region_code",
  "physical_country_id",
  "physical_country_iso_2",
  "physical_latitude",
  "physical_longitude",
  "physical_altitude",
  "domestic",
  "postal_address_part1",
  "postal_address_part2",
  "postal_address_part3",
  "postal_postcode",
  "postal_postplace",
  "postal_region_id",
  "postal_region_code",
  "postal_country_id",
  "postal_country_iso_2",
  "web_address",
  "email_address",
  "phone_number",
  "landline",
  "mobile_number",
  "fax_number",
  "unit_size_id",
  "unit_size_code",
  "status_id",
  "status_code",
  "used_for_counting",
  "last_edit_by_user_id",
  "last_edit_at",
  "has_legal_unit",
  "included_establishment_count",
  "included_legal_unit_count",
  "included_enterprise_count",
]);

const LTREE_COLUMNS = new Set([
  "primary_activity_category_path",
  "secondary_activity_category_path",
  "sector_path",
  "physical_region_path",
  "postal_region_path",
]);

const ARRAY_COLUMNS = new Set([
  "data_source_ids",
  "data_source_codes",
  "activity_category_paths",
  "tag_paths",
]);

const TSVECTOR_COLUMNS = new Set(["search"]);

const COMPARISON_OPERATORS: Record<string, string> = {
  eq: "=",
  neq: "<>",
  gt: ">",
  gte: ">=",
  lt: "<",
  lte: "<=",
};

const CODE_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** A double-quoted SQL identifier. */
export function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

/**
 * A SQL string literal. The route sets standard_conforming_strings = on, so a
 * backslash is an ordinary character and doubling single quotes is complete.
 * NUL cannot occur in a PostgreSQL text value and is refused.
 */
export function quoteLiteral(value: string): string {
  if (value.includes("\u0000")) {
    throw new ExportQueryError("Filter values cannot contain NUL characters");
  }
  return `'${value.replace(/'/g, "''")}'`;
}

/** A PostgreSQL array literal body `{"a","b"}` with element escaping. */
function arrayLiteral(elements: string[]): string {
  return `{${elements
    .map((element) => `"${element.replace(/[\\"]/g, (c) => `\\${c}`)}"`)
    .join(",")}}`;
}

/**
 * Split a PostgREST `in.(...)` / `ov.{...}` list body. Elements are separated
 * by commas; an element may be double-quoted to contain commas, with `\"` and
 * `\\` escapes inside quotes (PostgREST's grammar).
 */
export function splitListValues(body: string): string[] {
  const values: string[] = [];
  if (body === "") return values;
  let current = "";
  let inQuotes = false;
  let wasQuoted = false;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (inQuotes) {
      if (c === "\\" && i + 1 < body.length) {
        current += body[++i];
      } else if (c === '"') {
        inQuotes = false;
      } else {
        current += c;
      }
    } else if (c === '"' && current === "" && !wasQuoted) {
      inQuotes = true;
      wasQuoted = true;
    } else if (c === ",") {
      values.push(current);
      current = "";
      wasQuoted = false;
    } else {
      current += c;
    }
  }
  if (inQuotes) {
    throw new ExportQueryError(`Unterminated quote in list value: ${body}`);
  }
  values.push(current);
  return values;
}

type KeyKind =
  | "scalar"
  | "ltree"
  | "array"
  | "tsvector"
  | "jsonb"
  | "jsonb_text";

interface ResolvedKey {
  sql: string;
  kind: KeyKind;
}

/** Resolve a filter/order key to a SQL expression on `su`, or throw. */
function resolveKey(key: string): ResolvedKey {
  if (SCALAR_COLUMNS.has(key))
    return { sql: `su.${quoteIdent(key)}`, kind: "scalar" };
  if (LTREE_COLUMNS.has(key))
    return { sql: `su.${quoteIdent(key)}`, kind: "ltree" };
  if (ARRAY_COLUMNS.has(key))
    return { sql: `su.${quoteIdent(key)}`, kind: "array" };
  if (TSVECTOR_COLUMNS.has(key))
    return { sql: `su.${quoteIdent(key)}`, kind: "tsvector" };

  const externalIdent = /^external_idents->>(.+)$/.exec(key);
  if (externalIdent && CODE_PATTERN.test(externalIdent[1])) {
    return {
      sql: `(su.external_idents->>${quoteLiteral(externalIdent[1])})`,
      kind: "jsonb_text",
    };
  }
  const stat = /^stats_summary->(.+)->sum$/.exec(key);
  if (stat && CODE_PATTERN.test(stat[1])) {
    return {
      sql: `(su.stats_summary->${quoteLiteral(stat[1])}->'sum')`,
      kind: "jsonb",
    };
  }
  throw new ExportQueryError(
    `Unsupported export filter or order column: ${key}`
  );
}

/** Translate one `key=operator.value` filter into a SQL condition, or throw. */
export function filterCondition(key: string, rawValue: string): string {
  const { sql, kind } = resolveKey(key);

  const fts = /^fts(?:\(([a-z_]+)\))?\.([\s\S]*)$/.exec(rawValue);
  if (fts) {
    if (kind !== "tsvector") {
      throw new ExportQueryError(
        `fts is only supported on the search column, not ${key}`
      );
    }
    const config = fts[1] ?? "simple";
    return `${sql} @@ to_tsquery(${quoteLiteral(config)}::regconfig, ${quoteLiteral(fts[2])})`;
  }

  const dot = rawValue.indexOf(".");
  if (dot <= 0) {
    throw new ExportQueryError(
      `Unsupported filter value for ${key}: ${rawValue}`
    );
  }
  const operator = rawValue.slice(0, dot);
  const operand = rawValue.slice(dot + 1);

  if (operator === "is") {
    const isValues: Record<string, string> = {
      null: "NULL",
      true: "TRUE",
      false: "FALSE",
      unknown: "UNKNOWN",
    };
    const isValue = isValues[operand];
    if (!isValue) {
      throw new ExportQueryError(`Unsupported is.${operand} for ${key}`);
    }
    return `${sql} IS ${isValue}`;
  }

  if (operator in COMPARISON_OPERATORS) {
    if (kind === "tsvector" || kind === "array") {
      throw new ExportQueryError(
        `Operator ${operator} is not supported on ${key}`
      );
    }
    // jsonb keys compare as jsonb (PostgREST's `->` form); the literal is
    // coerced to the jsonb type, so numbers compare numerically.
    const literal =
      kind === "jsonb"
        ? `${quoteLiteral(operand)}::jsonb`
        : quoteLiteral(operand);
    return `${sql} ${COMPARISON_OPERATORS[operator]} ${literal}`;
  }

  if (operator === "in") {
    const list = /^\(([\s\S]*)\)$/.exec(operand);
    if (!list)
      throw new ExportQueryError(`in.(...) expected for ${key}: ${rawValue}`);
    if (kind === "tsvector" || kind === "array") {
      throw new ExportQueryError(`Operator in is not supported on ${key}`);
    }
    const literal = quoteLiteral(arrayLiteral(splitListValues(list[1])));
    return kind === "jsonb"
      ? `${sql} = ANY(${literal}::jsonb[])`
      : `${sql} = ANY(${literal})`;
  }

  if (operator === "like" || operator === "ilike") {
    if (kind !== "scalar" && kind !== "jsonb_text") {
      throw new ExportQueryError(
        `Operator ${operator} is not supported on ${key}`
      );
    }
    const pattern = operand.replace(/\*/g, "%");
    return `${sql} ${operator === "like" ? "LIKE" : "ILIKE"} ${quoteLiteral(pattern)}`;
  }

  if (operator === "cd") {
    if (kind !== "ltree")
      throw new ExportQueryError(
        `Operator cd is only supported on paths, not ${key}`
      );
    return `${sql} <@ ${quoteLiteral(operand)}::ltree`;
  }

  if (operator === "ov") {
    if (kind !== "array")
      throw new ExportQueryError(
        `Operator ov is only supported on arrays, not ${key}`
      );
    const list = /^\{([\s\S]*)\}$/.exec(operand);
    if (!list)
      throw new ExportQueryError(`ov.{...} expected for ${key}: ${rawValue}`);
    return `${sql} && ${quoteLiteral(arrayLiteral(splitListValues(list[1])))}`;
  }

  throw new ExportQueryError(
    `Unsupported filter operator for ${key}: ${operator}`
  );
}

/**
 * The export ORDER BY: the user's order plus the deterministic tiebreakers
 * (unit_type, unit_id, valid_from, valid_to) that identify a temporal row.
 * Each term is `key.asc|desc[.nullsfirst|.nullslast]`; without a nulls
 * modifier PostgreSQL's (and PostgREST's) default applies.
 */
export function orderByClause(order: string | null): string {
  const terms = (order || "name.asc")
    .split(",")
    .map((term) => term.trim())
    .filter(Boolean);
  const seen = new Set<string>();
  const parts: string[] = [];
  const addTerm = (term: string) => {
    const match = /^(.+?)(?:\.(asc|desc))?(?:\.(nullsfirst|nullslast))?$/.exec(
      term
    );
    if (!match) throw new ExportQueryError(`Unsupported order term: ${term}`);
    const [, key, direction, nulls] = match;
    const { sql, kind } = resolveKey(key);
    if (kind === "tsvector")
      throw new ExportQueryError(`Cannot order by ${key}`);
    seen.add(key);
    parts.push(
      `${sql} ${direction === "desc" ? "DESC" : "ASC"}${
        nulls === "nullsfirst"
          ? " NULLS FIRST"
          : nulls === "nullslast"
            ? " NULLS LAST"
            : ""
      }`
    );
  };
  terms.forEach(addTerm);
  for (const key of ["unit_type", "unit_id", "valid_from", "valid_to"]) {
    if (!seen.has(key)) addTerm(`${key}.asc`);
  }
  return parts.join(", ");
}

/** The WHERE conditions for all filter params (repeated keys are ANDed). */
export function whereConditions(params: URLSearchParams): string[] {
  const conditions: string[] = [];
  for (const [key, value] of params.entries()) {
    if (key === "order" || IGNORED_PARAMS.has(key)) continue;
    conditions.push(filterCondition(key, value));
  }
  return conditions;
}

function singleUnitType(params: URLSearchParams): string | null {
  const values = params.getAll("unit_type");
  if (values.length !== 1) return null;
  const list = /^in\.\(([\s\S]*)\)$/.exec(values[0]);
  if (!list) return null;
  const types = splitListValues(list[1]).filter((t) => t !== "");
  return types.length === 1 ? types[0] : null;
}

interface SelectColumn {
  name: string;
  sql: string;
}

/** The export columns in their explicit, historical order. */
export function exportColumns(
  config: ExportColumnConfig,
  params: URLSearchParams
): SelectColumn[] {
  const unitType = singleUnitType(params);
  const isEstablishment = unitType === "establishment";
  const plain = (name: string): SelectColumn => ({
    name,
    sql: `su.${quoteIdent(name)}`,
  });

  for (const code of [...config.externalIdentCodes, ...config.statCodes]) {
    if (!CODE_PATTERN.test(code)) {
      throw new ExportQueryError(`Unsupported column code: ${code}`);
    }
  }

  return [
    ...config.externalIdentCodes.map((code) => ({
      name: code,
      sql: `su.external_idents->>${quoteLiteral(code)}`,
    })),
    plain("valid_from"),
    plain("valid_to"),
    plain("name"),
    ...(unitType ? [] : [plain("unit_type")]),
    plain("birth_date"),
    plain("death_date"),
    plain("primary_activity_category_code"),
    { name: "primary_activity_category_name", sql: "pac.name" },
    plain("secondary_activity_category_code"),
    { name: "secondary_activity_category_name", sql: "sac.name" },
    ...(isEstablishment
      ? []
      : [plain("sector_code"), plain("legal_form_code")]),
    plain("physical_address_part1"),
    plain("physical_address_part2"),
    plain("physical_address_part3"),
    plain("physical_postcode"),
    plain("physical_postplace"),
    plain("physical_region_code"),
    { name: "physical_region_name", sql: "pr.name" },
    plain("physical_country_iso_2"),
    // numeric(?,6) would print its scale (63.000000); float8 prints the
    // shortest round-trip form, identical to the historical export.
    { name: "physical_latitude", sql: "su.physical_latitude::float8" },
    { name: "physical_longitude", sql: "su.physical_longitude::float8" },
    { name: "physical_altitude", sql: "su.physical_altitude::float8" },
    plain("postal_address_part1"),
    plain("postal_address_part2"),
    plain("postal_address_part3"),
    plain("postal_postcode"),
    plain("postal_postplace"),
    plain("postal_country_iso_2"),
    plain("web_address"),
    plain("email_address"),
    plain("phone_number"),
    plain("landline"),
    plain("mobile_number"),
    plain("fax_number"),
    plain("status_code"),
    plain("unit_size_code"),
    ...config.statCodes.map((code) => ({
      name: code,
      sql: `su.stats_summary->${quoteLiteral(code)}->'sum'`,
    })),
  ];
}

/** Compose the export SELECT and its count over the same filter. */
export function composeExportSql(
  params: URLSearchParams,
  config: ExportColumnConfig
): ExportSql {
  const conditions = whereConditions(params);
  const where = conditions.length
    ? `\nWHERE ${conditions.join("\n  AND ")}`
    : "";
  const columns = exportColumns(config, params);
  const orderBy = orderByClause(params.get("order"));

  const selectSql = `SELECT ${columns
    .map((column) => `${column.sql} AS ${quoteIdent(column.name)}`)
    .join(",\n       ")}
FROM public.statistical_unit AS su
LEFT JOIN LATERAL public.primary_activity_category(su) AS pac ON TRUE
LEFT JOIN LATERAL public.secondary_activity_category(su) AS sac ON TRUE
LEFT JOIN LATERAL public.physical_region(su) AS pr ON TRUE${where}
ORDER BY ${orderBy}`;

  const countSql = `SELECT count(*) AS total FROM public.statistical_unit AS su${where}`;

  return {
    selectSql,
    countSql,
    fieldNames: columns.map((column) => column.name),
  };
}
