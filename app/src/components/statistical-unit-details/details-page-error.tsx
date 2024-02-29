import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import DataDump from "@/components/data-dump";

interface ErrorPageParams {
  readonly error: Error & { digest?: string };
}

export default function DetailsPageError({error}: ErrorPageParams) {
  return (
    <DetailsPage title="This is what happened" subtitle="The following error happened while trying to get statistical unit information">
      <DataDump data={error}/>
    </DetailsPage>
  )
}
