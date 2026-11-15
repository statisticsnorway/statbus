import {
  legalFormSchema,
  sectorSchema,
} from "@/app/legal-units/[id]/classifications/validation";
import { demographicSchema } from "@/app/legal-units/[id]/demographic/validation";
import { generalInfoSchema } from "@/app/legal-units/[id]/general-info/validation";
import type { EditSchema } from "@/components/form/metadata-validation";

export function resolveSchemaByType(schemaType: SchemaType): EditSchema {
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
