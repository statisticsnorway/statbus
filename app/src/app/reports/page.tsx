import {Metadata} from "next";

export const metadata: Metadata = {
  title: "StatBus | Reports"
}

export default async function ReportsPage() {
  return (
    <main className="flex flex-col py-8 px-2 md:py-24 max-w-5xl mx-auto">
      <h1 className="font-medium text-xl text-center mb-12">StatBus Reports</h1>
      <p>Reports will soon appear here ...</p>
    </main>
  )
}
