import {Metadata} from "next"
import {Separator} from "@/components/ui/separator";
import {ReactNode} from "react";

export const metadata: Metadata = {
    title: "Details"
}

interface SettingsLayoutProps {
    readonly children: ReactNode,
    readonly header: ReactNode,
    readonly topology: ReactNode,
    readonly nav: ReactNode,
    readonly params: { id: string }
}

export default function SettingsLayout({children, header, topology, nav}: SettingsLayoutProps) {
    return (
        <main className="py-8 px-2 md:py-24 space-y-6 w-full max-w-5xl mx-auto">
            {header}
            <Separator className="my-6"/>
            <div className="flex flex-col space-y-8 lg:flex-row lg:space-x-12 lg:space-y-0">
                <aside className="lg:w-4/12">
                    {nav}
                    <div className="p-2 mt-6">
                        {topology}
                    </div>
                </aside>
                <div className="flex-1">{children}</div>
            </div>
        </main>
    )
}

