import { getServerClient } from "@/context/ClientStore";
import StatusOptions from "@/app/search/filters/status/status-options";

export default async function StatusFilter() {
  const client = await getServerClient();
  const { data: statuses } = await client
    .from("status")
    .select()
    .filter("active", "eq", true);

  return (
    <StatusOptions
      options={
        statuses?.map(({ code, name }) => ({
          label: name!,
          value: code!,
          humanReadableValue: name!,
        })) ?? []
      }
    />
  );
}
