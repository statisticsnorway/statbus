import { useEffect, useState } from "react";
export function useAuth() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    // Check session state from server
    async function checkAuth() {
      const response = await fetch('/api/auth/session');
      const data = await response.json();
      setIsAuthenticated(data.isAuthenticated);
    }

    checkAuth();
  }, []);

  return { isAuthenticated };
}
