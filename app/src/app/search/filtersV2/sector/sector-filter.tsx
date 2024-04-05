import { createClient } from "@/lib/supabase/server";
import SectorOptions from "@/app/search/filtersV2/sector/sector-options";

export default async function SectorFilter() {
  const client = createClient();
  const sectors = await client
    .from("sector_used")
    .select()
    .not("code", "is", null);

  await new Promise((resolve) => setTimeout(resolve, 1500));

  // TODO: remove demo delay
  // TODO: pass url search params to SectorOptions

  return (
    <SectorOptions
      options={
        sectors.data?.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })) ?? []
      }
      selected={[]}
    />
  );
}
