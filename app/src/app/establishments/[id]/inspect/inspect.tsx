"use client";
import { useEstablishment, useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import DataDump from "@/components/data-dump";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import useSWR from "swr";
import { getBrowserRestClient } from "@/context/RestClientStore";

function useExternalIdents(establishmentId: string) {
  const { data, isLoading, error } = useSWR(
    ["external_idents_establishment", establishmentId],
    async () => {
      const client = await getBrowserRestClient();
      const { data, error } = await client
        .from("external_ident")
        .select("*, external_ident_type:type_id(code, name, shape, labels)")
        .eq("establishment_id", parseInt(establishmentId, 10));
      if (error) throw error;
      return data;
    },
    { revalidateOnFocus: false }
  );
  return { externalIdents: data, isLoading, error };
}

export default function InspectDump({ id }: { readonly id: string }) {
  const { establishment, error: establishmentError } = useEstablishment(id);
  const { data: details, error: detailsError } = useStatisticalUnitDetails(id, "establishment");
  const { externalIdents, error: externalIdentsError } = useExternalIdents(id);

  if (establishmentError || !establishment) {
    return <UnitNotFound />;
  }

  const establishmentDetails = details?.establishment?.[0];

  return (
    <div className="space-y-6">
      <DataDump data={establishment} title="establishment (base table)" />
      
      {externalIdents && externalIdents.length > 0 && (
        <DataDump 
          data={externalIdents} 
          title="external_ident (related records)" 
        />
      )}

      {establishmentDetails && (
        <DataDump 
          data={establishmentDetails} 
          title="statistical_unit_details (computed view)" 
        />
      )}
    </div>
  );
}
