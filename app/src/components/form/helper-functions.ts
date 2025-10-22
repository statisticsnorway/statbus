import {
  legalFormSchema,
  sectorSchema,
} from "@/app/legal-units/[id]/classifications/validation";
import { demographicSchema } from "@/app/legal-units/[id]/demographic/validation";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import { z } from "zod";

export function resolveSchemaByType(schemaType: SchemaType): z.Schema {
  switch (schemaType) {
    case "general-info":
      return generalInfoSchema;
    case "demographic-info":
      return demographicSchema;
    case "sector":
      return sectorSchema;
    case "legal-form":
      return legalFormSchema;
    default:
      throw new Error(`Unknown schema type: ${schemaType}`);
  }
}

export function checkValidityBounds(
  overlappingRows: { valid_from: string | null; valid_to: string | null }[],
  valid_from: string,
  valid_to: string,
  tableName: string
): UpdateResponse | null {
  const minValidFrom = overlappingRows
    .map((r) => r.valid_from)
    .filter((d): d is string => d !== null)
    .reduce((min, d) => (d < min ? d : min));

  const maxValidTo = overlappingRows
    .map((r) => r.valid_to)
    .filter((d): d is string => d !== null)
    .reduce((max, d) => (d > max ? d : max));

  const extendsBefore = valid_from < minValidFrom;
  const extendsAfter = valid_to > maxValidTo;

  if (extendsAfter || extendsBefore) {
    const overlapDetails = [];

    if (extendsBefore) {
      overlapDetails.push(
        `the provided valid from (${valid_from}) is before the earliest valid from (${minValidFrom})`
      );
    }

    if (extendsAfter) {
      overlapDetails.push(
        `the provided valid to (${valid_to}) is after the latest valid to (${maxValidTo})`
      );
    }

    return {
      status: "error",
      message: `Cannot update ${tableName}: ${overlapDetails.join(" and ")} for this record. Date range must be fully within or fully outside the existing range.`,
    };
  }
  return null;
}
