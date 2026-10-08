/**
 * The canonical unit existence rule (STATBUS-460), as PostgREST filters.
 *
 * A unit EXISTS at instant d iff
 *     COALESCE(birth_date, valid_from) <= d
 * AND (death_date IS NULL OR death_date > d)
 * AND valid_until > d
 * for the record whose validity window covers d. The database implements it
 * once (public.unit_existence_from / public.unit_existence_until) and exposes
 * it as the computed fields `existence_from` and `existence_until` on
 * statistical_unit, legal_unit and establishment, so every screen that answers
 * "which units exist at d" filters:
 *
 *     existence_from=lte.<d>&existence_until=gt.<d>
 *
 * The old screen predicate `valid_from=lte.<d>&valid_to=gte.<d>` asked a
 * different question ("does a RECORD cover d") and counted units before their
 * birth date and after their death date (STATBUS-458).
 *
 * Use these helpers instead of spelling the filter by hand, so there is one
 * place in the app that says what "exists" means.
 */

export const EXISTENCE_FROM = "existence_from";
export const EXISTENCE_UNTIL = "existence_until";

/** The two PostgREST query parameters that select units existing at validOn. */
export function existenceSearchParams(validOn: string): [string, string][] {
  return [
    [EXISTENCE_FROM, `lte.${validOn}`],
    [EXISTENCE_UNTIL, `gt.${validOn}`],
  ];
}

/** Set the existence filter on a URLSearchParams (replacing any previous one). */
export function setExistenceSearchParams(
  params: URLSearchParams,
  validOn: string
): void {
  for (const [key, value] of existenceSearchParams(validOn)) {
    params.set(key, value);
  }
}

/** The minimal builder surface the existence filter needs (PostgREST filter builders). */
interface ComparableFilterBuilder {
  lte(column: string, value: string): this;
  gt(column: string, value: string): this;
}

/**
 * Apply the existence filter to a postgrest-js query on statistical_unit,
 * legal_unit or establishment. The computed fields are not table columns, so
 * the generated column types do not list them; the filter is passed by name.
 */
export function whereExistsOn<Q extends ComparableFilterBuilder>(
  query: Q,
  validOn: string
): Q {
  return query.lte(EXISTENCE_FROM, validOn).gt(EXISTENCE_UNTIL, validOn);
}
