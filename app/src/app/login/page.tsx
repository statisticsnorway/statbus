import React from "react";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import LoginClientBoundary from "./LoginClientBoundary"; 

// LoginPage is now a simple component.
// All redirection logic (if user is already authenticated or becomes authenticated)
// is handled by LoginClientBoundary on the client-side.
export default function LoginPage() {
  if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
    console.log("LoginPage: Rendering login page structure. Client-side will handle auth checks and redirects.");
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
        <LoginClientBoundary />
      </div>
    </main>
  );
}
