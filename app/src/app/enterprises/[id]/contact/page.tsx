import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEnterpriseById} from "@/components/statistical-unit-details/requests";

export default async function EnterpriseContactPage({params: {id}}: { readonly params: { id: string } }) {
  const {unit, error} = await getEnterpriseById(id)

  if (error) {
    throw error
  }

  if (!unit) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show the contact information for enterprise {unit.id}
      </p>
    </DetailsPage>
  )
}

