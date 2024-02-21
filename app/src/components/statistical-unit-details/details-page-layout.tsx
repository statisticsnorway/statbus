import {ReactNode} from "react";

export interface DetailsPageLayoutProps {
  readonly children: ReactNode,
  readonly header: ReactNode,
  readonly topology: ReactNode,
  readonly nav: ReactNode
}

export const DetailsPageLayout = ({children, header, topology, nav}: DetailsPageLayoutProps) => (
  <main className="py-2 px-2 lg:py-24 space-y-6 w-full max-w-5xl mx-auto">
    {header}
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
