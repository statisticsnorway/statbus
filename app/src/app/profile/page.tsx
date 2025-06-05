export const dynamic = 'force-dynamic';

import { redirect } from "next/navigation";
import LogoutForm from "./LogoutForm";
import { logger } from "@/lib/client-logger";
import { authStore } from "@/context/AuthStore";
import { getServerRestClient } from "@/context/RestClientStore";

export default async function ProfilePage() {
  try {
    // Get authentication status from AuthStore
    const authStatus = await authStore.getAuthStatus();
    
    if (!authStatus.isAuthenticated || !authStatus.user) {
      const errorMessage = "User not found. Cannot retrieve profile.";
      logger.error({ context: "ProfilePage" }, errorMessage);
      redirect('/login');
    }
    
    // All user details are now in the AuthStore
    const client = await getServerRestClient();
    const { data, error } = await client.rpc('auth_status');
    
    if (error) {
      logger.error({ context: "ProfilePage", error }, "Error fetching user details");
      redirect('/login');
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
                  {authStatus.user.uid}
                </dd>
              </div>
              <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt className="text-sm font-medium leading-6 text-gray-900">
                  Full name
                </dt>
                <dd className="mt-1 text-sm capitalize leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                  {authStatus.user.email?.split("@")[0].replace(/\./, " ")}
                </dd>
              </div>
              <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt className="text-sm font-medium leading-6 text-gray-900">
                  Email address
                </dt>
                <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                  {authStatus.user.email}
                </dd>
              </div>
              <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt className="text-sm font-medium leading-6 text-gray-900">
                  Role
                </dt>
                <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                  {authStatus.user.statbus_role}
                </dd>
              </div>
              <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt className="text-sm font-medium leading-6 text-gray-900">
                  Last sign in
                </dt>
                <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                  {authStatus.user.last_sign_in_at ? new Date(authStatus.user.last_sign_in_at).toLocaleString() : "N/A"}
                </dd>
              </div>
              <div className="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt className="text-sm font-medium leading-6 text-gray-900">
                  Account created
                </dt>
                <dd className="mt-1 text-sm leading-6 text-gray-700 sm:col-span-2 sm:mt-0">
                  {authStatus.user.created_at ? new Date(authStatus.user.created_at).toLocaleString() : "N/A"}
                </dd>
              </div>
            </dl>
          </div>
          <LogoutForm />
        </div>
      </main>
    );
  } catch (error) {
    logger.error({ context: "ProfilePage", error }, "Error loading profile page");
    redirect('/login');
  }
}
