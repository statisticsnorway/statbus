import { getServerRestClient } from "@/context/RestClientStore";
import SectorOptions from "@/app/search/filters/sector/sector-options";

export default async function SectorFilter() {
  const client = await getServerRestClient();
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
