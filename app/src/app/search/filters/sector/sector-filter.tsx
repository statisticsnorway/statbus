import { getServerClient } from "@/context/ClientStore";
import SectorOptions from "@/app/search/filters/sector/sector-options";

export default async function SectorFilter() {
  const client = await getServerClient();
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
    />
  );
}
