import { DetailsPage } from "@/components/statistical-unit-details/details-page";

export default function NotFound() {
  return (
    <DetailsPage
      title="Legal unit not found"
      subtitle="Could not find the legal unit you're looking for"
    >
      <p className="bg-gray-50 p-12 text-center text-sm">
        Check the URL and try again
      </p>
    </DetailsPage>
  );
}
