import React from "react";
import Link from "next/link";

export default async function ImportPage() {
  return (
    <div className="space-y-6 text-center">
      <h1 className="text-center text-2xl">Welcome</h1>
      <p>
        In this onboarding guide we will try to help you get going with Statbus.
      </p>
      <Link className="block underline" href="/import/legal-units">
        Start
      </Link>
    </div>
  );
}
