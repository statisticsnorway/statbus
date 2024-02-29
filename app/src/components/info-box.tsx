import React, {ReactNode} from "react";
import {Info} from "lucide-react";

export const InfoBox = ({children}: { readonly children: ReactNode }) => (
  <div className="p-6 bg-amber-100 leading-loose space-y-6">
    {children}
  </div>
)
