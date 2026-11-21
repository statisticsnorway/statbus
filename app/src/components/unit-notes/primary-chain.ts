/**
 * The primary chain a unit page shows notes for (64ae2w, owner 2026-11-20 and
 * 2026-11-21): always in the fixed order enterprise, legal unit, establishment,
 * the same on all three pages. The page's own unit is marked current: its note
 * is the open "Notes" with the pencil, on top; the others follow below it in
 * the chain's order as small post-its named by their role.
 * A unit that is not on the primary chain (a non-primary legal unit or
 * establishment) takes the chain's place at its level, so the page's own note
 * is always in the box.
 */
import type { NotesUnitColumn } from "./unit-notes";
import { enterpriseName } from "@/lib/enterprise-name";

export interface ChainUnit {
  column: NotesUnitColumn;
  id: number;
  /** The unit's name, shown inside its opened post-it as the link to its page. */
  name: string;
  /** The unit's role on the chain, as its post-it names it: "Primary legal unit", "Primary establishment", "Enterprise" (see primaryChain). */
  kind: string;
  href: string;
  current: boolean;
}

type Hierarchy = {
  enterprise?: {
    id: number;
    short_name?: string | null;
    legal_unit?: { id: number; name: string; primary_for_enterprise: boolean; establishment?: { id: number; name: string; primary_for_legal_unit: boolean }[] }[];
    establishment?: { id: number; name: string; primary_for_enterprise: boolean }[];
  };
};

const ENTERPRISE = { column: "enterprise_id" as const, kind: "Enterprise", path: "enterprises" };
const LEGAL_UNIT = { column: "legal_unit_id" as const, kind: "Legal unit", path: "legal-units" };
const ESTABLISHMENT = { column: "establishment_id" as const, kind: "Establishment", path: "establishments" };

/**
 * The chain for the page of unit `current` (its notes column and id), read
 * from the unit's hierarchy at the page's time frame, in the order enterprise,
 * legal unit, establishment. Without a hierarchy (the unit does not exist in
 * the frame) the chain is the page's own unit alone, named `currentName`.
 *
 * A legal unit or establishment is named "Primary ..." when it is the primary
 * one; a non-primary one, present only because it is the page's own unit, is
 * named plainly.
 */
export function primaryChain(
  hierarchy: Hierarchy | null | undefined,
  current: { column: NotesUnitColumn; id: number },
  currentName = ""
): ChainUnit[] {
  const enterprise = hierarchy?.enterprise;
  const unit = (level: typeof ENTERPRISE | typeof LEGAL_UNIT | typeof ESTABLISHMENT, id: number, name: string, primary: boolean): ChainUnit => ({
    column: level.column,
    id,
    name,
    kind: primary ? `Primary ${level.kind.toLowerCase()}` : level.kind,
    href: `/${level.path}/${id}`,
    current: level.column === current.column && id === current.id,
  });
  if (!enterprise) {
    const level = [ENTERPRISE, LEGAL_UNIT, ESTABLISHMENT].find((l) => l.column === current.column);
    return level ? [unit(level, current.id, currentName, false)] : [];
  }

  const legalUnits = enterprise.legal_unit ?? [];
  const allEstablishments = [
    ...(enterprise.establishment ?? []),
    ...legalUnits.flatMap((lu) => lu.establishment ?? []),
  ];
  const currentLegalUnit =
    current.column === "legal_unit_id"
      ? legalUnits.find((lu) => lu.id === current.id)
      : current.column === "establishment_id"
        ? legalUnits.find((lu) => lu.establishment?.some((e) => e.id === current.id))
        : undefined;
  const legalUnit = currentLegalUnit ?? legalUnits.find((lu) => lu.primary_for_enterprise);
  const currentEstablishment =
    current.column === "establishment_id" ? allEstablishments.find((e) => e.id === current.id) : undefined;
  const establishment =
    currentEstablishment ??
    (legalUnit
      ? legalUnit.establishment?.find((e) => e.primary_for_legal_unit)
      : enterprise.establishment?.find((e) => e.primary_for_enterprise));

  const chain: ChainUnit[] = [
    unit(ENTERPRISE, enterprise.id, enterpriseName({ short_name: enterprise.short_name, legal_unit: legalUnits, establishment: enterprise.establishment }) ?? `#${enterprise.id}`, false),
  ];
  if (legalUnit) chain.push(unit(LEGAL_UNIT, legalUnit.id, legalUnit.name, legalUnit.primary_for_enterprise));
  if (establishment) {
    const primary = "primary_for_legal_unit" in establishment ? establishment.primary_for_legal_unit : establishment.primary_for_enterprise;
    chain.push(unit(ESTABLISHMENT, establishment.id, establishment.name, primary));
  }
  return chain;
}
