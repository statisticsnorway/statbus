import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<Tables<"stat_definition">[], string> = async (key) => {
  const client = await getBrowserRestClient();
  const { data, error } = await client
    .from("stat_definition")
    .select("*")
    .order("priority");

  if (error) {
    throw new Error(error.message, { cause: error });
  }

  return data;
};

export function useStatDefinitions() {
  const { data, error, isLoading, mutate } = useSWR(
    "/admin/stat_definition",
    fetcher
  );

  return {
    statDefinitions: data ?? [],
    isLoading,
    error,
    refreshStatDefinitions: mutate,
  };
}
