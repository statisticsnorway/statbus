"use client";
import { DetailsPage } from "@/components/statistical-unit-details/details-page";
import { logger } from "@/lib/client-logger";

interface ErrorPageParams {
  readonly error: Error & { digest?: string };
}

export default function DetailsPageError({ error }: ErrorPageParams) {
  logger.error("DetailsPageError", "Statistical unit details page failed", { error });

  return (
    <DetailsPage
      title="This is what happened"
      subtitle="The following error happened while trying to get statistical unit information"
    >
      <div className="space-y-6 bg-red-100 p-6">
        {error.message && (
          <ErrorSection title="Error Message" body={error.message} />
        )}
        {error.stack && <ErrorSection title="Stack" body={error.stack} />}
        {error.digest && <ErrorSection title="Digest" body={error.digest} />}
      </div>
    </DetailsPage>
  );
}

const ErrorSection = ({ title, body }: { title: string; body: string }) => (
  <div>
    <h2 className="mb-0.5 text-xs font-semibold uppercase">{title}:</h2>
    <p>{body}</p>
  </div>
);
