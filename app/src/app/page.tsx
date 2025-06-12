"use client"; // Convert to client component

import { useEffect, useState } from "react"; // Import useState
import { useAtomValue } from "jotai";
import { appReadyAtom } from "@/atoms";
import Dashboard from "@/app/dashboard/page";

// For dynamic titles in client components, useEffect is typically used.
// import { Metadata } from "next"; // Metadata export removed
import { deploymentSlotName } from "@/lib/deployment-variables";

// export const metadata: Metadata = { // Metadata export removed
//   title: `${deploymentSlotName} Statbus | Home`,
// };

// Note: 'export const dynamic = 'force-dynamic';' is typically for Server Components.
// Its effect on a Client Component page that wraps a Server Component (Dashboard) might be indirect.
// We'll keep it for now as it was pre-existing.
export const dynamic = 'force-dynamic'; 

export default function HomePage() {
  const appReadyState = useAtomValue(appReadyAtom);
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
    // Optionally set document title if client-side updates are preferred for SPA feel
    // document.title = `${deploymentSlotName} Statbus | Home`;
  }, []);

  if (!isMounted || !appReadyState.isReadyToRenderDashboard) {
    // If not mounted yet, render a consistent fallback (or nothing specific for the loading messages part)
    // to match server render. The main layout's Suspense fallback will handle the overall page skeleton.
    // Once mounted, then allow appReadyState to control the specific loading messages.
    // The spinner can be shown immediately as it's not dependent on client-only state.
    // The main layout (layout.tsx) already provides NavbarSkeleton and FooterSkeleton.
    // This component should only provide a loading state for its content area.
    return (
      <main className="flex-grow p-4 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-gray-900 mx-auto mb-4"></div>
          {isMounted && appReadyState.isLoadingAuth && <p>Authenticating...</p>}
          {isMounted && appReadyState.isAuthenticated && appReadyState.isLoadingBaseData && <p>Loading core data...</p>}
          {/* Removed messages related to isLoadingGettingStartedData and isSetupComplete */}
          {/* Fallback message if auth and base data are loaded but dashboard isn't ready for other reasons (should be rare now) */}
          { isMounted && appReadyState.isAuthProcessComplete && 
            appReadyState.isAuthenticated && 
            appReadyState.isBaseDataLoaded && 
            !appReadyState.isReadyToRenderDashboard &&
            <p>Preparing dashboard...</p>
          }
          {!isMounted && <p>Loading...</p>} {/* Generic message if not yet mounted */}
        </div>
      </main>
    );
  }

  // Once ready, render the actual Dashboard component
  return <Dashboard />;
}
