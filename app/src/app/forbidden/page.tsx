import Link from "next/link";

export default function ForbiddenPage() {
  return (
    <main className="flex flex-col items-center justify-center text-center">
      <h1 className="text-xl font-bold">403 - Forbidden</h1>
      <p className="mt-4 text-sm">
        You don’t have permission to access this page.
      </p>
      <Link href="/" className="mt-6 text-sm text-blue-500 hover:underline">
        Return to Home
      </Link>
    </main>
  );
}
