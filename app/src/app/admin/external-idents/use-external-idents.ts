import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<Tables<"external_ident_type">[], string> = async (
  key
) => {
  const client = await getBrowserRestClient();
  const { data, error } = await client
    .from("external_ident_type")
    .select("*")
    .order("priority");

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  return data;
};

export function useExternalIdentTypes() {
  const { data, error, isLoading, mutate } = useSWR(
    "/admin/external_ident_type",
    fetcher
  );

  return {
    externalIdentTypes: data ?? [],
    isLoading,
    error,
    refreshExternalIdentTypes: mutate,
  };
}
