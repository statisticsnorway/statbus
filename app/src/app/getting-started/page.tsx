import React from "react";
import Link from "next/link";

export default async function GettingStartedPage() {
  return (
    <div className="space-y-6 text-center">
      <h1 className="text-center text-xl">Welcome</h1>
      <p>
        In this onboarding guide we will try to help you get going with StatBus.
        We will assist you in selecting an activity standard and you will get to
        upload your first region data set.
      </p>

      <Link
        className="block underline"
        href="/getting-started/activity-standard"
      >
        Start
      </Link>
    </div>
  );
}
