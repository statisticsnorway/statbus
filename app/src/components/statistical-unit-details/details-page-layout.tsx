import { ReactNode } from "react";

export interface DetailsPageLayoutProps {
  readonly children: ReactNode;
  readonly header: ReactNode;
  readonly nav: ReactNode;
}

export const DetailsPageLayout = ({
  children,
  header,
  nav,
}: DetailsPageLayoutProps) => (
  <main className="mx-auto w-full max-w-5xl space-y-6 px-2 py-2 lg:py-12">
    {header}
    <div className="flex flex-col lg:flex-row space-x-4 space-y-8  lg:space-y-0">
      <aside className="lg:w-3/12">{nav}</aside>
      <div className="lg:w-9/12">
        <div className="flex-1">{children}</div>
      </div>
    </div>
  </main>
);
