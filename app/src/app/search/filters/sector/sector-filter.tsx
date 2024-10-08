import { createSupabaseSSRClient } from "@/utils/supabase/server";
import SectorOptions from "@/app/search/filters/sector/sector-options";

interface IProps {
  readonly urlSearchParam: string | null;
}

export default async function SectorFilter({ urlSearchParam }: IProps) {
  const client = await createSupabaseSSRClient();
  const sectors = await client.from("sector_used").select();

  return (
    <SectorOptions
      options={
        sectors.data?.map(({ code, path, name }) => ({
          label: code ? `${code} ${name}` : `${name}`,
          value: path as string,
          humanReadableValue: code ? `${code} ${name}` : `${name}`,
        })) ?? []
      }
      selected={urlSearchParam ? urlSearchParam.split(",") : []}
    />
  );
}
