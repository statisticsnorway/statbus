import { AlertCircle } from "lucide-react";
import React, { ReactNode } from "react";

export const ErrorBox = ({ children }: { readonly children: ReactNode }) => (
  <div className="flex items-center space-x-3 bg-red-100 p-6">
    <div>
      <AlertCircle size={32} />
    </div>
    {children}
  </div>
);
