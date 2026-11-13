/**
 * The options of a country list on an edit form: the installation's own
 * country first (settings.country_id, set up in Getting started), since most
 * units' addresses are domestic; then every other country by name. Without a
 * configured country, all by name.
 */
export function countryOptions(
  countries: readonly { id: number | null; name: string | null }[],
  domesticCountryId: number | null | undefined
): { value: number; label: string }[] {
  const options = countries
    .filter((c): c is { id: number; name: string | null } => c.id != null)
    .map((c) => ({ value: c.id, label: c.name ?? "" }))
    .sort((a, b) => a.label.localeCompare(b.label, "en"));
  const domestic = options.find((o) => o.value === domesticCountryId);
  return domestic ? [domestic, ...options.filter((o) => o !== domestic)] : options;
}
