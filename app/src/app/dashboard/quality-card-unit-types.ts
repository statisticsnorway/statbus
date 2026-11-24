/**
 * The unit types a data-quality card counts and lists: legal units and
 * establishments, the units that carry their own location, activity and
 * region. Enterprises and power groups take these from their legal units, so
 * a problem shows once, on the unit that has it. The card's count selects
 * these types and its link lists them, so the card and its list ask the same
 * question (dwt9kd).
 */
export const QUALITY_CARD_UNIT_TYPES = ["legal_unit", "establishment"] as const;

/** The Statistical Units list parameter for QUALITY_CARD_UNIT_TYPES. */
export const QUALITY_CARD_UNIT_TYPE_PARAM = `unit_type=${QUALITY_CARD_UNIT_TYPES.join(",")}`;
