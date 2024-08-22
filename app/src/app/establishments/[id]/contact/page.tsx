import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { notFound } from "next/navigation";
import { getEstablishmentById } from "@/components/statistical-unit-details/requests";
import { Metadata } from "next";

export const metadata: Metadata = {
  title: "Establishment | Contact",
};

export default async function EstablishmentContactPage({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  const { establishment, error } = await getEstablishmentById(id);

  if (error) {
    throw error;
  }

  if (!establishment) {
    notFound();
  }

  return (
    <DetailsPage
      title="Contact Info"
      subtitle="Contact information such as email, phone, and addresses"
    >
      <p className="bg-gray-50 p-12 text-center text-sm">
        This section will show the contact information for {establishment.name}
      </p>
    </DetailsPage>
  );
}
