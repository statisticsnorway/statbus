import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import StatusOptions from "@/app/search/filters/status/status-options";

export default async function StatusFilter() {
  const client = await createPostgRESTSSRClient();
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
