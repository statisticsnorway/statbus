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
      // Force a hard redirect instead of using Next.js redirect
      // This ensures the redirect happens even if there are issues with Next.js redirect
      if (typeof window !== 'undefined') {
        window.location.href = '/';
        return null; // Return null to prevent rendering while redirect happens
      } else {
        redirect('/');
      }
    } else {
      console.log("LoginPage: User is not authenticated, showing login form");
    }
  } catch (error) {
    console.error("Error checking authentication status:", error);
    // Continue to login page if there's an error checking auth status
  }

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
