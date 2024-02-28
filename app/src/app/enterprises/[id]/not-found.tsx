import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export default function NotFound () {
  return (
    <DetailsPage title="Statistical unit not found" subtitle="Could not find the statistical unit you're asking for">
      <p className="bg-gray-50 p-12 text-sm text-center">
        Check the URL and try again
      </p>
    </DetailsPage>
  )
}
