import {logout} from "@/app/login/actions";
import {createClient} from "@/lib/supabase/server";

export default async function ProfilePage() {
  const client = createClient()
  const {data: {session}} = await client.auth.getSession()

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-8 md:p-24">
      <div className="mx-auto sm:w-full lg:max-w-5xl">
        <div>
          <h3 className="text-base font-semibold leading-7 text-gray-900">Profile Information</h3>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-gray-500">This is what the system knows about you</p>
        </div>
        <div className="mt-6 border-t border-gray-100">
          <dl className="divide-y divide-gray-100">
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">User ID</dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user?.id}</dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">Full name</dt>
              <dd
                className="mt-1 text-sm capitalize leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user?.email?.split("@")[0].replace(/\./, " ")}</dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">Email address</dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user?.email}</dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">Phone</dt>
              <dd
                className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user.phone || "N/A"}</dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">Last sign in</dt>
              <dd
                className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user.last_sign_in_at}</dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">Email confirmed</dt>
              <dd
                className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">{session?.user.email_confirmed_at}</dd>
            </div>
          </dl>
        </div>
        <form action={logout} className="bg-gray-100 p-6 flex justify-end">
          <button
            type="submit"
            className="text-white bg-gray-800 hover:bg-gray-900 focus:outline-none focus:ring-2 focus:ring-indigo-600 font-medium rounded-md text-sm px-5 py-2.5 me-2">
            Log out
          </button>
        </form>
      </div>
    </main>
  )
}
