import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEstablishmentById} from "@/components/statistical-unit-details/requests";

export default async function EstablishmentGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getEstablishmentById(id);

  if (error) {
    throw error
  }

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, sector">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show general information for {unit.name}
      </p>
    </DetailsPage>
  )
}

