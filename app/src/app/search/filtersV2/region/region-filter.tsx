import { createClient } from "@/lib/supabase/server";
import RegionOptions from "@/app/search/filtersV2/region/region-options";

export default async function RegionFilter() {
  const client = createClient();
  const regions = await client.from("region_used").select();

  await new Promise((resolve) => setTimeout(resolve, 1500));

  // TODO: remove demo delay
  // TODO: pass url search params to Child Component

  return (
    <RegionOptions
      options={[
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...(regions.data?.map(({ code, path, name }) => ({
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })) ?? []),
      ]}
      selected={[]}
    />
  );
}
