import {
  composeExportSql,
  exportColumns,
  ExportQueryError,
  filterCondition,
  orderByClause,
  quoteLiteral,
  splitListValues,
} from "./export-sql";

const config = {
  externalIdentCodes: ["tax_ident", "stat_ident"],
  statCodes: ["employees", "turnover"],
};

describe("filterCondition: the search page's PostgREST syntax", () => {
  it("translates in.(...) into = ANY of an array literal", () => {
    expect(filterCondition("unit_type", "in.(legal_unit,establishment)")).toBe(
      `su."unit_type" = ANY('{"legal_unit","establishment"}')`
    );
  });

  it("translates ltree containment (cd.) and missing paths (is.null)", () => {
    expect(filterCondition("physical_region_path", "cd.03.01")).toBe(
      `su."physical_region_path" <@ '03.01'::ltree`
    );
    expect(filterCondition("sector_path", "is.null")).toBe(
      `su."sector_path" IS NULL`
    );
  });

  it("translates full-text search with its configuration", () => {
    expect(filterCondition("search", "fts(simple).'bifrost':* & !'as':*")).toBe(
      `su."search" @@ to_tsquery('simple'::regconfig, '''bifrost'':* & !''as'':*')`
    );
  });

  it("translates array overlap (ov.) for data sources", () => {
    expect(filterCondition("data_source_ids", "ov.{1,2}")).toBe(
      `su."data_source_ids" && '{"1","2"}'`
    );
  });

  it("compares external identifiers as text and statistics as jsonb", () => {
    expect(filterCondition("external_idents->>tax_ident", "eq.921826885")).toBe(
      `(su.external_idents->>'tax_ident') = '921826885'`
    );
    expect(
      filterCondition("external_idents->>census", "like.CENSUS2024.*")
    ).toBe(`(su.external_idents->>'census') LIKE 'CENSUS2024.%'`);
    expect(filterCondition("stats_summary->employees->sum", "gte.100")).toBe(
      `(su.stats_summary->'employees'->'sum') >= '100'::jsonb`
    );
    expect(filterCondition("stats_summary->employees->sum", "in.(7,8)")).toBe(
      `(su.stats_summary->'employees'->'sum') = ANY('{"7","8"}'::jsonb[])`
    );
  });

  it("translates boolean is.true / is.false", () => {
    expect(filterCondition("domestic", "is.false")).toBe(
      `su."domestic" IS FALSE`
    );
  });

  it("keeps hostile values inside one literal", () => {
    expect(filterCondition("name", "eq.x'); DROP TABLE t; --")).toBe(
      `su."name" = 'x''); DROP TABLE t; --'`
    );
    expect(filterCondition("legal_form_code", `in.("a,b","c\\"d",'e')`)).toBe(
      `su."legal_form_code" = ANY('{"a,b","c\\"d","''e''"}')`
    );
  });

  it("rejects unknown columns rather than ignoring them", () => {
    expect(() => filterCondition("password", "eq.x")).toThrow(ExportQueryError);
    expect(() => filterCondition("name;drop", "eq.x")).toThrow(
      ExportQueryError
    );
    expect(() => filterCondition("external_idents->>a'b", "eq.x")).toThrow(
      ExportQueryError
    );
    expect(() => filterCondition("stats_summary->x->max", "eq.1")).toThrow(
      ExportQueryError
    );
  });

  it("rejects unknown operators and operators that do not fit the column", () => {
    expect(() => filterCondition("name", "match.x")).toThrow(ExportQueryError);
    expect(() => filterCondition("name", "nonsense")).toThrow(ExportQueryError);
    expect(() => filterCondition("name", "cd.a")).toThrow(ExportQueryError);
    expect(() => filterCondition("name", "fts.x")).toThrow(ExportQueryError);
    expect(() => filterCondition("data_source_ids", "eq.1")).toThrow(
      ExportQueryError
    );
    expect(() => filterCondition("domestic", "is.maybe")).toThrow(
      ExportQueryError
    );
    expect(() => filterCondition("name", "in.a,b")).toThrow(ExportQueryError);
  });

  it("refuses NUL characters", () => {
    expect(() => quoteLiteral("a\u0000b")).toThrow(ExportQueryError);
  });
});

describe("splitListValues", () => {
  it("splits on commas and honours quoted elements", () => {
    expect(splitListValues("a,b")).toEqual(["a", "b"]);
    expect(splitListValues(`"a,b",c`)).toEqual(["a,b", "c"]);
    expect(splitListValues(`"x\\"y"`)).toEqual(['x"y']);
    expect(splitListValues("")).toEqual([]);
  });

  it("rejects an unterminated quote", () => {
    expect(() => splitListValues(`"abc`)).toThrow(ExportQueryError);
  });
});

describe("orderByClause", () => {
  it("appends the temporal-identity tiebreakers once", () => {
    expect(orderByClause(null)).toBe(
      `su."name" ASC, su."unit_type" ASC, su."unit_id" ASC, su."valid_from" ASC, su."valid_to" ASC`
    );
    expect(orderByClause("birth_date.desc,unit_type.asc,unit_id.asc")).toBe(
      `su."birth_date" DESC, su."unit_type" ASC, su."unit_id" ASC, su."valid_from" ASC, su."valid_to" ASC`
    );
  });

  it("orders by jsonb keys and honours nulls modifiers", () => {
    expect(
      orderByClause("stats_summary->employees->sum.desc.nullslast")
    ).toMatch(/^\(su\.stats_summary->'employees'->'sum'\) DESC NULLS LAST, /);
    expect(orderByClause("external_idents->>tax_ident.asc")).toMatch(
      /^\(su\.external_idents->>'tax_ident'\) ASC, /
    );
  });

  it("rejects unknown order columns", () => {
    expect(() => orderByClause("pg_sleep(10).asc")).toThrow(ExportQueryError);
    expect(() => orderByClause("search.asc")).toThrow(ExportQueryError);
  });
});

describe("exportColumns: explicit column order", () => {
  it("keeps each name directly after its code, identifiers first, statistics last", () => {
    const names = exportColumns(config, new URLSearchParams()).map(
      (c) => c.name
    );
    expect(names.slice(0, 2)).toEqual(["tax_ident", "stat_ident"]);
    expect(names.slice(-2)).toEqual(["employees", "turnover"]);
    const after = (code: string) => names[names.indexOf(code) + 1];
    expect(after("primary_activity_category_code")).toBe(
      "primary_activity_category_name"
    );
    expect(after("secondary_activity_category_code")).toBe(
      "secondary_activity_category_name"
    );
    expect(after("physical_region_code")).toBe("physical_region_name");
    expect(names).toContain("unit_type");
    expect(names).toContain("sector_code");
  });

  it("drops unit_type for a single type and sector/legal form for establishments", () => {
    const names = exportColumns(
      config,
      new URLSearchParams({ unit_type: "in.(establishment)" })
    ).map((c) => c.name);
    expect(names).not.toContain("unit_type");
    expect(names).not.toContain("sector_code");
    expect(names).not.toContain("legal_form_code");
  });

  it("rejects configured codes that are not plain identifiers", () => {
    expect(() =>
      exportColumns(
        { externalIdentCodes: ["a'b"], statCodes: [] },
        new URLSearchParams()
      )
    ).toThrow(ExportQueryError);
  });
});

describe("composeExportSql", () => {
  const sql = composeExportSql(
    new URLSearchParams({
      unit_type: "in.(legal_unit,establishment)",
      physical_region_path: "cd.03",
      order: "name.asc,unit_type.asc,unit_id.asc",
      limit: "10",
      offset: "20",
      select: "ignored",
    }),
    config
  );

  it("never pages: limit/offset/select do not reach the SQL", () => {
    expect(sql.selectSql).not.toMatch(/LIMIT|OFFSET|ignored/);
  });

  it("joins the computed names laterally, so rows without them survive", () => {
    expect(sql.selectSql).toContain(
      "LEFT JOIN LATERAL public.primary_activity_category(su) AS pac ON TRUE"
    );
    expect(sql.selectSql).toContain(
      "LEFT JOIN LATERAL public.physical_region(su) AS pr ON TRUE"
    );
  });

  it("counts over exactly the same WHERE clause", () => {
    const where = sql.selectSql
      .slice(sql.selectSql.indexOf("WHERE"), sql.selectSql.indexOf("ORDER BY"))
      .trim();
    expect(sql.countSql.endsWith(where)).toBe(true);
  });

  it("ANDs repeated filters on one key (range conditions)", () => {
    const params = new URLSearchParams();
    params.append("stats_summary->employees->sum", "gte.100");
    params.append("stats_summary->employees->sum", "lt.150");
    const { countSql } = composeExportSql(params, config);
    expect(countSql).toContain(">= '100'::jsonb");
    expect(countSql).toContain("< '150'::jsonb");
  });
});
