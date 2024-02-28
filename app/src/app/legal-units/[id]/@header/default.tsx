import {getLegalUnitById} from "@/app/_statistical-unit-details/legal-unit-requests";
import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const {legalUnit, error} = await getLegalUnitById(id);

  if (error) {
    return (
      <DetailsPageHeader
        title="Something went wrong"
        subtitle={`Could not find a legal unit with ID ${id}`}
        className="bg-legal_unit-50 border-indigo-100"/>
    )
  }

  if (!legalUnit) {
    return (
      <DetailsPageHeader
        title="Legal Unit Not Found"
        subtitle={`Could not find a legal unit with ID ${id}`}
        className="bg-legal_unit-50 border-indigo-100"/>
    )
  }

  return (
    <DetailsPageHeader title={legalUnit.name} className="bg-legal_unit-50 border-lime-100"/>
  )
}

