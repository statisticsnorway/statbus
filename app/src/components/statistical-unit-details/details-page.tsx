import { ReactNode } from "react";
import { Separator } from "@/components/ui/separator";

/**
 * One section of a unit details page.
 * `wide` marks content that needs the full screen width, such as the history
 * table: DetailsPageLayout then lifts its readable max
 * width (see the `data-wide-content` selector there). Forms leave it off.
 */
export const DetailsPage = ({
  title,
  subtitle,
  wide = false,
  children,
}: {
  readonly title: string;
  readonly subtitle: string;
  readonly wide?: boolean;
  readonly children?: ReactNode;
}) => (
  <div className="space-y-4" data-wide-content={wide ? "" : undefined}>
    <div>
      <h3 className="text-lg font-medium">{title}</h3>
      <p className="text-muted-foreground text-sm">{subtitle}</p>
    </div>
    <Separator />
    {children}
  </div>
);
