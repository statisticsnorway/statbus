import { createClient } from "@/lib/supabase/server";
import SectorOptions from "@/app/search/filtersV2/sector/sector-options";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default async function SectorFilter({ urlSearchParam }: IProps) {
  const client = createClient();
  const sectors = await client
    .from("sector_used")
    .select()
    .not("code", "is", null);

  // TODO: remove demo delay
  await new Promise((resolve) => setTimeout(resolve, 1500));

  return (
    <SectorOptions
      options={
        sectors.data?.map(({ code, name }) => ({
          label: `${code} ${name}`,
          value: code,
        })) ?? []
      }
      selected={urlSearchParam ? urlSearchParam.split(",") : []}
    />
  );
}
