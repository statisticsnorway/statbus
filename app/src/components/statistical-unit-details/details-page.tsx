import {ReactNode} from "react";
import {Separator} from "@/components/ui/separator";

export const DetailsPage = ({title, subtitle, children}: {
  readonly title: string,
  readonly subtitle: string,
  readonly children: ReactNode
}) => (
  <div className="space-y-6">
    <div>
      <h3 className="text-lg font-medium">{title}</h3>
      <p className="text-sm text-muted-foreground">
        {subtitle}
      </p>
    </div>
    <Separator/>
    {children}
  </div>
)
