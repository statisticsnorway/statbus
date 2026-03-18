import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<Tables<"status">[], string> = async (key) => {
  const client = await getBrowserRestClient();
  const { data, error } = await client
    .from("status")
    .select("*")
    .order("priority")

  if (error) {
    throw new Error(error.message, { cause: error });
  }
  return data;
};

export function useStatusCodes() {
  const { data, error, isLoading, mutate } = useSWR("/admin/status", fetcher);
  return {
    statusCodes: data ?? [],
    isLoading,
    error,
    refreshStatusCodes: mutate,
  };
}

