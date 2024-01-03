import React from "react";
import Link from "next/link";

export default async function Home() {
  return (
    <div className="text-center space-y-6">
      <h1 className="font-medium text-lg">Welcome!</h1>
      <p>
        In this onboarding guide we will try to help you get going with Statbus.
        We will assist you in selecting an activity standard and you will get
        to upload your first region data set.
      </p>

      <Link className="block underline" href="/getting-started/activity-standard">Start</Link>
    </div>
  )
}
