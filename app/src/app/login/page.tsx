import React from "react";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import LoginForm from "./LoginForm";
import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { authStore } from "@/context/AuthStore";

export default async function LoginPage() {
  try {
    // Check authentication status server-side
    console.log("LoginPage: Checking authentication status...");
    const authStatus = await authStore.getAuthStatus();
    console.log("LoginPage: Auth status:", JSON.stringify({
      isAuthenticated: authStatus.isAuthenticated,
      hasUser: !!authStatus.user,
      userEmail: authStatus.user?.email || 'none'
    }, null, 2));
    
    // If already authenticated, redirect to home
    if (authStatus.isAuthenticated) {
      console.log("LoginPage: User is authenticated, redirecting to home...");
      redirect('/'); 
      // Note: redirect() throws a special error NEXT_REDIRECT, 
      // which is handled by Next.js and won't be caught below.
    } else {
      console.log("LoginPage: User is not authenticated, showing login form");
    }
  } catch (error) {
    // This catch block will only handle errors from authStore.getAuthStatus()
    console.error("Error checking authentication status:", error);
    // If checking auth status fails, proceed to show the login form.
  }

  // If not redirected (i.e., not authenticated or error during check), render the login page
  return (
    <main className="px-6 py-24 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-sm">
        <Image
          src={logo}
          alt="Statbus Logo"
          width={32}
          height={32}
          className="mx-auto h-10 w-auto"
        />
        <h2 className="mt-10 text-center text-2xl font-bold leading-9 tracking-tight text-gray-900">
          Sign in to your account
        </h2>
      </div>

      <div className="mt-10 sm:mx-auto sm:w-full sm:max-w-sm">
        <LoginForm />
      </div>
    </main>
  );
}
