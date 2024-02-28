import {getEstablishmentById} from "@/app/_statistical-unit-details/establishment-requests";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";

export default async function EstablishmentGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const {establishment, error} = await getEstablishmentById(id);

  if (error) {
    throw error
  }

  if (!establishment) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, sector">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show general information for {establishment.name}
      </p>
    </DetailsPage>
  )
}

