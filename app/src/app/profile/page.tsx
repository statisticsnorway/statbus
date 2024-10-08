import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { logger } from "@/lib/client-logger";
import LogoutForm from "./LogoutForm";

export default async function ProfilePage() {
  const client = await createSupabaseSSRClient();
  const {data: {user}} = await client.auth.getUser();

  if (!user) {
    const errorMessage = "User not found. Cannot retrieve profile.";
    logger.error({ context: "ProfilePage", user }, errorMessage);
    throw new Error(errorMessage);
  }

  return (
    <main className="flex flex-col items-center justify-between px-2 py-8 md:py-24">
      <div className="mx-auto sm:w-full lg:max-w-5xl">
        <div>
          <h3 className="text-base font-semibold leading-7 text-gray-900">
            Profile Information
          </h3>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-gray-500">
            This is what the system knows about you
          </p>
        </div>
        <div className="mt-6 border-t border-gray-100">
          <dl className="divide-y divide-gray-100">
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                User ID
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.id}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Full name
              </dt>
              <dd className="mt-1 text-sm capitalize leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.email?.split("@")[0].replace(/\./, " ")}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Email address
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.email}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Phone
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.phone || "N/A"}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Last sign in
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.last_sign_in_at}
              </dd>
            </div>
            <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
              <dt className="text-sm font-medium leading-6 text-gray-900">
                Email confirmed
              </dt>
              <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                {user.email_confirmed_at}
              </dd>
            </div>
          </dl>
        </div>
        <LogoutForm />
      </div>
    </main>
  );
}
