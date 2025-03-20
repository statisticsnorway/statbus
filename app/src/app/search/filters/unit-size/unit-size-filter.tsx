import { createSupabaseSSRClient } from "@/utils/supabase/server";
import UnitSizeOptions from "@/app/search/filters/unit-size/unit-size-options";

export default async function UnitSizeFilter() {
  const client = await createSupabaseSSRClient();
  const { data: unitSizes } = await client
    .from("unit_size")
    .select()
    .filter("active", "eq", true);

  return (
    <UnitSizeOptions
      options={
        unitSizes?.map(({ code, name }) => ({
          label: name!,
          value: code!,
          humanReadableValue: name!,
        })) ?? []
      }
    />
  );
}
