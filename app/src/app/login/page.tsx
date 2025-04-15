import React from "react";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import LoginForm from "./LoginForm";
import { redirect } from "next/navigation";
import { cookies } from "next/headers";

export default async function LoginPage() {
  // We don't need server-side redirect logic here
  // Authentication redirects are handled by middleware

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
