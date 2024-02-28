'use client';

import {DetailsPage} from "@/components/statistical-unit-details/details-page";

interface ErrorPageParams {
  readonly error: Error & { digest?: string };
  readonly reset: () => void;
}

export default function ErrorPage(_props: ErrorPageParams) {
  return (
    <DetailsPage title="Something went wrong" subtitle="Failed to get legal unit information">
      <p className="bg-gray-50 p-12 text-sm text-center">
        Something went wrong. Please try again later.
      </p>
    </DetailsPage>
  )
}
