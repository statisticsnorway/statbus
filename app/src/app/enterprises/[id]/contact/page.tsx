import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getEnterpriseById } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";

export const metadata: Metadata = {
  title: "Enterprise | Contact",
};

export default async function EnterpriseContactPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { enterprise, error } = await getEnterpriseById(id);

  if (error) {
    throw error;
  }

  if (!enterprise) {
    notFound();
  }

  return (
    <DetailsPage
      title="Contact Info"
      subtitle="Contact information such as email, phone, and addresses"
    >
      <p className="bg-gray-50 p-12 text-center text-sm">
        This section will show the contact information for enterprise{" "}
        {enterprise.id}
      </p>
    </DetailsPage>
  );
}
