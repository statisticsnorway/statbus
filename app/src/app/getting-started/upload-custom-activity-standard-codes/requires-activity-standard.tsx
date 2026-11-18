import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { InfoBox } from "@/components/info-box";

/**
 * Custom activity codes extend the activity category standard chosen in
 * Getting started step 2; the database checks each code against it. Until a
 * standard is set, this shows the way to step 2 in place of the upload.
 */
export function RequiresActivityStandard({
  settings,
  children,
}: {
  readonly settings: { activity_category_standard: { id: number; name: string } | null } | null;
  readonly children: React.ReactNode;
}) {
  if (settings?.activity_category_standard) return <>{children}</>;
  return (
    <InfoBox>
      <div className="flex justify-between items-center gap-4">
        <p>
          Select the activity category standard in step 2 first. Custom codes
          extend that standard.
        </p>
        <Link
          href="/getting-started/activity-standard"
          className={buttonVariants({ variant: "outline" })}
        >
          Go to step 2
        </Link>
      </div>
    </InfoBox>
  );
}
