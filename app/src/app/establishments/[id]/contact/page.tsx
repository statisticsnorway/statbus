import {getEstablishmentById} from "@/app/_requests/establishment-requests";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";

export default async function EstablishmentContactPage({params: {id}}: { readonly params: { id: string } }) {
  const {establishment, error} = await getEstablishmentById(id);

  if (error) {
    throw error
  }

  if (!establishment) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show the contact information for {establishment.name}
      </p>
    </DetailsPage>
  )
}

