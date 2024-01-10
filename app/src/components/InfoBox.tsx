import React, {ReactNode} from "react";
import {Info} from "lucide-react";

export const InfoBox = ({children}: { readonly children: ReactNode }) => (
  <div className="flex items-center space-x-3 p-6 bg-amber-100">
    <div>
      <Info/>
    </div>
    {children}
  </div>
)
