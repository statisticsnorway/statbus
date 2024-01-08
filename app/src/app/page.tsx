import Link from "next/link";

export default async function Home() {
  return (
    <main className="flex flex-col items-center p-24">
      <h1 className="font-medium text-lg mb-3">Welcome to Statbus!</h1>
      <span>
        Head over <Link className="underline" href="/getting-started">here</Link> to get started.
      </span>
    </main>
  )
}
