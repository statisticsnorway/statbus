import { ImportUnitsProvider } from "./import-units-context";

export default function ImportLayout({
  children,
  progress,
}: {
  readonly children: React.ReactNode;
  readonly progress: React.ReactNode;
}) {
  return (
    <ImportUnitsProvider>
      <main className="w-full mx-auto max-w-screen-xl px-2 py-8 md:py-12 grid lg:grid-cols-12 gap-8">
        <aside className="p-6 pb-12 col-span-12 lg:col-span-4 bg-ssb-light">
          {progress}
        </aside>
        <div className="flex-1 col-span-12 lg:col-span-8 py-6">
          <div className="max-w-2xl mx-auto">{children}</div>
        </div>
      </main>
    </ImportUnitsProvider>
  );
}
