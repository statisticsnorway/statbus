import {getEstablishmentById} from "@/app/establishments/[id]/establishment-requests";
import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";

export default async function EstablishmentContactPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEstablishmentById(id);

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show the contact information for {unit.name}
      </p>
    </DetailsPage>
  )
}

