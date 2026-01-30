"use client";
import { useLegalUnit, useStatisticalUnitDetails } from "@/components/statistical-unit-details/use-unit-details";
import DataDump from "@/components/data-dump";
import UnitNotFound from "@/components/statistical-unit-details/unit-not-found";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { useSWRWithAuthRefresh, isJwtExpiredError, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

function useExternalIdents(legalUnitId: string) {
  const { data, isLoading, error } = useSWRWithAuthRefresh(
    ["external_idents", legalUnitId],
    async () => {
      const client = await getBrowserRestClient();
      const { data, error } = await client
        .from("external_ident")
        .select("*, external_ident_type:type_id(code, name, shape, labels)")
        .eq("legal_unit_id", parseInt(legalUnitId, 10));
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return data;
    },
    { revalidateOnFocus: false },
    "useExternalIdents:legalUnit"
  );
  return { externalIdents: data, isLoading, error };
}

export default function InspectDump({ id }: { readonly id: string }) {
  const { legalUnit, error: legalUnitError } = useLegalUnit(id);
  const { data: details, error: detailsError } = useStatisticalUnitDetails(id, "legal_unit");
  const { externalIdents, error: externalIdentsError } = useExternalIdents(id);

  if (legalUnitError || !legalUnit) {
    return <UnitNotFound />;
  }

  const legalUnitDetails = details?.legal_unit?.[0];

  return (
    <div className="space-y-6">
      <DataDump data={legalUnit} title="legal_unit (base table)" />
      
      {externalIdents && externalIdents.length > 0 && (
        <DataDump 
          data={externalIdents} 
          title="external_ident (related records)" 
        />
      )}

      {legalUnitDetails && (
        <DataDump 
          data={legalUnitDetails} 
          title="statistical_unit_details (computed view)" 
        />
      )}
    </div>
  );
}
