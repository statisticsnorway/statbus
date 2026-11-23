import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { UnitsMap } from "@/components/map/units-map";

/** The units of this enterprise's enterprise on a map (z2qt08, owner 2026-11-23). */
export default async function EnterpriseMapPage(props: { readonly params: Promise<{ id: string }> }) {
  const { id } = await props.params;
  return (
    <DetailsPage title="Map" subtitle="Where the units of this enterprise are">
      <UnitsMap unitId={id} unitType="enterprise" />
    </DetailsPage>
  );
}
