import React, {ReactNode} from "react";
import {cn} from "@/lib/utils";

export const InfoBox = ({children, className}: { readonly children: ReactNode, readonly className?: string }) => (
    <div className={cn("p-6 bg-amber-100 leading-loose space-y-6", className)}>
        {children}
    </div>
)
