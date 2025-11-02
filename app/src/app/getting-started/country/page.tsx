export const dynamic = "force-dynamic";

import React from "react";
import CountryForm from "@/app/getting-started/country/country-form";
import { getServerRestClient } from "@/context/RestClientStore";

export default async function CountryPage() {
  const client = await getServerRestClient();

  const { data: countries, error: countriesError } = await client
    .from("country")
    .select()
    .order("name");

  if (countriesError) {
    console.error("Countries fetch error:", {
      error: countriesError,
    });
  }

  const { data: settings } = await client.from("settings").select();

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Select Installation Country</h1>
      <p>
        Select the country for this register. This is used to identify which
        businesses are domestic and which are foreign.
      </p>
      <CountryForm countries={countries} settings={settings} />
    </section>
  );
}
