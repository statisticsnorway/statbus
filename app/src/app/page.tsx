export default async function Home() {
  return (
    <main className="flex flex-col py-8 px-2 md:py-24 max-w-5xl mx-auto">
      <h1 className="font-medium text-xl text-center">Statbus Dashboard</h1>
      <h2 className="font-medium text-sm text-gray-700 text-center mb-12">Coming soon</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div className="col-span-1 bg-gray-100 text-center p-12 py-24 text-gray-500"></div>
        <div className="col-span-1 bg-gray-100 text-center p-12 py-24 text-gray-500"></div>
        <div className="col-span-1 bg-gray-100 text-center p-12 py-24 text-gray-500"></div>
        <div className="col-span-1 bg-gray-100 text-center p-12 py-24 text-gray-500"></div>
        <div className="col-span-1 bg-gray-100 text-center p-12 py-24 text-gray-500"></div>
      </div>
    </main>
  )
}
