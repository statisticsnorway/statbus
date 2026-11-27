import type { Enums } from "@/lib/database.types";

/**
 * A data-quality rule (public.quality_rule): the kinds of check the database knows. A rule that
 * compares a summed statistical variable (public.quality_rule_per_stat) is a check per variable.
 */
export type QualityRule = Enums<"quality_rule">;

/** Where a check's findings are stored (public.quality_check_kind). */
export type QualityCheckKind = Enums<"quality_check_kind">;

/** One check of public.quality_check, as a search reads it: its id, rule and kind of store. */
export interface QualityCheckRef {
  /** public.quality_check.id: the number in statistical_unit.quality_check_ids or a relation table. */
  readonly id: number;
  readonly rule: QualityRule;
  readonly kind: QualityCheckKind;
}

interface QualityRuleWording {
  /** The check's name on its card and in the Quality filter, for the variable named statName. */
  readonly name: (statName: string | null) => string;
  /** What the check lists and why it is worth a look: the ⓘ text, one or two sentences. */
  readonly explanation: (statName: string | null) => string;
  /** The Methodological Guideline section that explains the rule, when there is one. */
  readonly guideHref?: string;
}

const COUNTING_GUIDE_HREF =
  "https://github.com/statisticsnorway/statbus/blob/master/doc/METHODOLOGICAL_GUIDELINE.md#323-how-statistical-variables-add-up-between-legal-units-and-establishments";

const variable = (statName: string | null) => statName ?? "Variable";

/**
 * The wording of every rule. Keyed by the database enum, so a rule added to public.quality_rule
 * fails the type check until it has a name and an explanation here.
 */
export const QUALITY_RULE_WORDING: Record<QualityRule, QualityRuleWording> = {
  missing_region: {
    name: () => "Units missing region",
    explanation: () =>
      "Legal units and establishments located in this country whose physical location has no region. They are left out of every report by region.",
  },
  missing_activity_category: {
    name: () => "Units missing activity category",
    explanation: () =>
      "Legal units and establishments without a primary activity category. They are left out of every report by activity.",
  },
  missing_physical_location: {
    name: () => "Units missing physical location",
    explanation: () =>
      "Legal units and establishments without a physical location, for example after Remove took it away for part of their life. They have no country or region in any report.",
  },
  establishment_activity_differs: {
    name: () => "Establishment has another activity",
    explanation: () =>
      "Legal units whose primary establishment has another primary activity category than the legal unit. Usually one of the two was not updated.",
  },
  establishments_above_legal_unit: {
    name: (statName) => `${variable(statName)}: establishments add up to more than the legal unit`,
    explanation: (statName) =>
      `Legal units whose establishments' ${variable(statName).toLowerCase()} add up to more than the legal unit's own value. The establishments are parts of the legal unit, so one of the two levels is wrong; the legal unit counts the establishments' sum.`,
    guideHref: COUNTING_GUIDE_HREF,
  },
  legal_unit_above_establishments: {
    name: (statName) =>
      `${variable(statName)}: legal unit has more than its establishments, all of which have numbers`,
    explanation: (statName) =>
      `Legal units whose own ${variable(statName).toLowerCase()} is larger than their establishments' sum while every establishment has a value. Nothing explains the rest: often an establishment, such as the head office, is missing.`,
    guideHref: COUNTING_GUIDE_HREF,
  },
  secondary_activity_equals_primary: {
    name: () => "Secondary activity equals primary",
    explanation: () =>
      "Legal units and establishments whose secondary activity category is the same as their primary one for some period. A secondary activity is another activity than the primary, so it should be changed or removed.",
  },
};

/** The name of a check, with its variable's stat_definition.name for a per-variable rule. */
export function qualityCheckName(rule: QualityRule, statName: string | null): string {
  return QUALITY_RULE_WORDING[rule].name(statName);
}

/** The ⓘ explanation of a check. */
export function qualityCheckExplanation(rule: QualityRule, statName: string | null): string {
  return QUALITY_RULE_WORDING[rule].explanation(statName);
}

/**
 * The URL value of a check in ?quality=: the rule, and for a per-variable rule its variable's code,
 * e.g. missing_region or establishments_above_legal_unit:employees.
 */
export function qualityCheckParam(rule: QualityRule, statCode: string | null): string {
  return statCode ? `${rule}:${statCode}` : rule;
}

/**
 * The unit types a check lists: legal units and establishments for the rules about a unit's own
 * location and activity, legal units for the rules comparing a legal unit with its establishments.
 */
export const QUALITY_RULE_UNIT_TYPES: Record<QualityRule, readonly ("legal_unit" | "establishment")[]> = {
  missing_region: ["legal_unit", "establishment"],
  missing_activity_category: ["legal_unit", "establishment"],
  missing_physical_location: ["legal_unit", "establishment"],
  establishment_activity_differs: ["legal_unit"],
  establishments_above_legal_unit: ["legal_unit"],
  legal_unit_above_establishments: ["legal_unit"],
  secondary_activity_equals_primary: ["legal_unit", "establishment"],
};

/**
 * The Statistical Units list a check's card opens: the units the check lists, the same set the card
 * counts, e.g. /search?unit_type=legal_unit&quality=establishments_above_legal_unit:employees.
 */
export function qualityCheckHref(rule: QualityRule, statCode: string | null): string {
  return `/search?unit_type=${QUALITY_RULE_UNIT_TYPES[rule].join(",")}&quality=${qualityCheckParam(rule, statCode)}`;
}

const QUALITY_RULES = new Set<string>(Object.keys(QUALITY_RULE_WORDING));

export function isQualityRule(value: string): value is QualityRule {
  return QUALITY_RULES.has(value);
}

/** The rule and variable code of a ?quality= value; null when the value names no rule. */
export function parseQualityCheckParam(
  value: string | null
): { rule: QualityRule; statCode: string | null } | null {
  if (!value) return null;
  const [rule, statCode, ...rest] = value.split(":");
  if (rest.length > 0 || !isQualityRule(rule)) return null;
  return { rule, statCode: statCode && /^[a-z0-9_]+$/.test(statCode) ? statCode : null };
}
