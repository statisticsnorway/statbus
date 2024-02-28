import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export default function NotFound () {
  return (
    <DetailsPage title="Establishment not found" subtitle="Could not find the establishment you're looking for">
      <p className="bg-gray-50 p-12 text-sm text-center">
        Check the URL and try again
      </p>
    </DetailsPage>
  )
}
