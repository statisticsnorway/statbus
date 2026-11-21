/**
 * Which edits of a primary unit change another unit (ep47vn), field by field,
 * as public.timeline_enterprise_def derives them (doc/primary-units.md):
 * values flow upward only, from an enterprise's primary legal unit (or, for an
 * enterprise without legal units, its primary establishment) to the
 * enterprise. Nothing in a legal unit comes from its primary establishment.
 *
 * Keys are the edit forms' field ids (fieldId, fieldGroupId).
 */

/** What an edit of this field changes in the enterprise, or null when it changes nothing there. */
export type EnterpriseEffect = "name" | "value";

const FLOWS_TO_ENTERPRISE: Record<string, EnterpriseEffect> = {
  name: "name",
  "physical-location": "value",
  "postal-location": "value",
  "contact-info": "value",
  demographic: "value",
  primary_category_id: "value",
  secondary_category_id: "value",
  sector_id: "value",
};

/** legal_form_id comes from the primary legal unit only (no establishment fallback). */
const FLOWS_FROM_LEGAL_UNIT_ONLY = new Set(["legal_form_id"]);

/**
 * Whether saving `fieldId` on a unit that is primary for its enterprise changes
 * the enterprise. The enterprise's name follows the primary unit only while the
 * enterprise has no short name of its own. Identifiers, statistics and the
 * image do not flow: the enterprise keeps its own identifiers, and its
 * statistics are summed over all its units, not taken from the primary one.
 */
export function editChangesEnterprise(
  fieldId: string,
  primary: "legal_unit" | "establishment",
  enterpriseHasShortName: boolean
): boolean {
  if (FLOWS_FROM_LEGAL_UNIT_ONLY.has(fieldId)) return primary === "legal_unit";
  const effect = FLOWS_TO_ENTERPRISE[fieldId];
  if (!effect) return false;
  return effect === "name" ? !enterpriseHasShortName : true;
}
