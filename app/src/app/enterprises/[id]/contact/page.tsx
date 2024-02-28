import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEnterpriseById} from "@/app/enterprises/[id]/enterprise-requests";

export default async function EnterpriseContactPage({params: {id}}: { readonly params: { id: string } }) {
  const {enterprise, error} = await getEnterpriseById(id);
  const name = `Enterprise ${enterprise?.id}`;

  if (error) {
    throw error
  }

  if (!enterprise) {
    notFound()
  }

  return (
    <DetailsPage title="Contact Info" subtitle="Contact information such as email, phone, and addresses">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show the contact information for {name}
      </p>
    </DetailsPage>
  )
}

