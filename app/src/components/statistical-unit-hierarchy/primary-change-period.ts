import type { TimeFrame } from "@/lib/time-frame";
import type { ValidityChoice } from "@/components/time-frame-panel";

/**
 * The period a Set as primary applies to (2f4c0z): the chosen time frame's period, or the user's own
 * dates. Dates are ISO yyyy-mm-dd and valid_to is inclusive ("infinity" for no end), as the database
 * functions set_primary_establishment_for_legal_unit and set_primary_legal_unit_for_enterprise take
 * them. Null when the choice is incomplete (no frame, or no From date).
 */
export function primaryChangePeriod(
  choice: ValidityChoice,
  frame: Pick<TimeFrame, "valid_from" | "valid_to"> | null | undefined,
  validFrom: string | null,
  validTo: string | null
): { validFrom: string; validTo: string } | null {
  if (choice === "frame") {
    if (!frame?.valid_from || !frame.valid_to) return null;
    return { validFrom: frame.valid_from, validTo: frame.valid_to };
  }
  if (!validFrom) return null;
  return { validFrom, validTo: validTo || "infinity" };
}

/** The live frame, where a change lands unless the user picks another frame. */
export function liveFrame<T extends Pick<TimeFrame, "kind">>(frames: readonly T[]): T | undefined {
  return frames.find((f) => f.kind === "live");
}
