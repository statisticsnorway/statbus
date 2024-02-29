import {notFound} from "next/navigation";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {getEnterpriseById, getStatisticalUnitHierarchy} from "@/components/statistical-unit-details/requests";
import DataDump from "@/components/data-dump";

export default async function EnterpriseDetailsPage({params: {id}}: { readonly params: { id: string } }) {
  const {enterprise, error} = await getEnterpriseById(id)
  const {hierarchy, error: hierarchyError} = await getStatisticalUnitHierarchy(parseInt(id, 10), "enterprise")

  if (error) {
    throw new Error(error.message, {cause: error})
  }

  if (hierarchyError) {
    throw new Error(hierarchyError.message, {cause: hierarchyError})
  }

  if (!enterprise || !hierarchy) {
    notFound()
  }

  const primaryLegalUnit = hierarchy.enterprise?.legal_unit.find(lu => lu.primary)
  if (!primaryLegalUnit) {
    throw new Error("No primary legal unit found")
  }

  const {activity, location, establishment: _, ...rest} = primaryLegalUnit

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, sector">
      <DataDump title="enterprise" data={enterprise}/>
      <DataDump title="legal unit general info" data={rest}/>
      <DataDump title="legal unit location" data={location}/>
      <DataDump title="legal unit activity" data={activity}/>
    </DetailsPage>
  )
}
