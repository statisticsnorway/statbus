import {getEstablishmentById} from "@/app/_statistical-unit-details/establishment-requests";
import {DetailsPageHeader} from "@/components/statistical-unit-details/details-page-header";

export default async function HeaderSlot({params: {id}}: { readonly params: { id: string } }) {
  const {establishment, error} = await getEstablishmentById(id);

  if (error) {
    return (
      <DetailsPageHeader
        title="Something went wrong"
        subtitle={`Could not find an establishment with ID ${id}`}
        className="bg-establishment-50 border-indigo-100"/>
    )
  }

  if (!establishment) {
    return (
      <DetailsPageHeader
        title="Establishment Not Found"
        subtitle={`Could not find an establishment with ID ${id}`}
        className="bg-establishment-50 border-indigo-100"/>
    )
  }

  return (
    <DetailsPageHeader title={establishment.name} className="bg-establishment-50 border-indigo-100"/>
  )
}
