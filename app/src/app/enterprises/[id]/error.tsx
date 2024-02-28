'use client';

import {DetailsPage} from "@/components/statistical-unit-details/details-page";

export default function Error ({error, reset}: {error: Error & { digest?: string }, reset: () => void}) {
  return (
    <DetailsPage title="Something went wrong" subtitle="Failed to get statistical unit information">
      <p className="bg-gray-50 p-12 text-sm text-center">
        Something went wrong. Please try again later.
      </p>
    </DetailsPage>
  )
}
