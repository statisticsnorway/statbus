import { ReactNode } from "react";

export interface DetailsPageLayoutProps {
  readonly children: ReactNode;
  readonly header: ReactNode;
  readonly topology: ReactNode;
  readonly nav: ReactNode;
}

export const DetailsPageLayout = ({
  children,
  header,
  topology,
  nav,
}: DetailsPageLayoutProps) => (
  <main className="mx-auto w-full max-w-5xl space-y-6 px-2 py-2 lg:py-24">
    {header}
    <div className="flex flex-col space-y-8 lg:flex-row lg:space-x-12 lg:space-y-0">
      <aside className="lg:w-6/12">
        {nav}
        <div className="mt-6 p-2">{topology}</div>
      </aside>
      <div className="flex-1">{children}</div>
    </div>
  </main>
);
