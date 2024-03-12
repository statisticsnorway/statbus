"use client";

import DetailsPageError from "@/components/statistical-unit-details/details-page-error";

export default function ErrorPage({
  error,
}: {
  readonly error: Error & { digest?: string };
}) {
  return <DetailsPageError error={error} />;
}
