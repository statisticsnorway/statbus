/**
 * The name an enterprise goes by, as the database derives it for search and reports
 * (public.timeline_enterprise_def): its own short name when set, else its primary
 * legal unit's name, else its primary establishment's.
 */
export function enterpriseName(enterprise: {
  short_name?: string | null;
  legal_unit?: { primary_for_enterprise: boolean; name: string | null }[];
  establishment?: { primary_for_enterprise: boolean; name: string | null }[];
}): string | null {
  const shortName = enterprise.short_name?.trim();
  if (shortName) return shortName;
  return derivedEnterpriseName(enterprise);
}

/** The name an enterprise has while its short name is empty: its primary unit's. */
export function derivedEnterpriseName(enterprise: {
  legal_unit?: { primary_for_enterprise: boolean; name: string | null }[];
  establishment?: { primary_for_enterprise: boolean; name: string | null }[];
}): string | null {
  const primary =
    enterprise.legal_unit?.find((lu) => lu.primary_for_enterprise) ??
    enterprise.establishment?.find((es) => es.primary_for_enterprise);
  return primary?.name ?? null;
}
