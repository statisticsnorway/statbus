"use client";

import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
import { login as apiLogin, logout as apiLogout, refreshToken } from '@/services/auth';
import { useRouter } from 'next/navigation';
import { User, authStore } from '@/context/AuthStore';

interface AuthContextType {
  isAuthenticated: boolean;
  user: User | null;
  isLoading: boolean;
  refreshAuth: () => Promise<void>;
  logout: () => Promise<void>;
  login: (email: string, password: string) => Promise<any>;
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const router = useRouter();
  
  const refreshAuth = useCallback(async (): Promise<AuthStatus> => { // Return AuthStatus
    try {
      setIsLoading(true);
      
      // Get complete auth status from the AuthStore
      try {
        const authStatus = await authStore.getAuthStatus();
        
        if (process.env.NODE_ENV === 'development') {
          console.debug('Auth status result:', authStatus);
        }
        
        setIsAuthenticated(authStatus.isAuthenticated);
        setUser(authStatus.user);
        
        // If token is expiring soon, refresh it proactively
        if (authStatus.tokenExpiring) {
          await refreshToken();
          // Get updated auth status after token refresh
          const updatedStatus = await authStore.getAuthStatus();
          setIsAuthenticated(updatedStatus.isAuthenticated);
          setUser(updatedStatus.user);
        }
      } catch (error) {
        console.error('Error getting auth status:', error);
        setIsAuthenticated(false);
        setUser(null);
      }
    } catch (error) {
      console.error('Error refreshing auth:', error);
      setIsAuthenticated(false);
      setUser(null);
      // Ensure a consistent return type on error
      return { isAuthenticated: false, user: null, tokenExpiring: false };
    } finally {
      setIsLoading(false);
    }
  }, [setIsLoading, setIsAuthenticated, setUser]); // Dependencies for refreshAuth
  
  const handleLogin = async (email: string, password: string) => {
    try {
      setIsLoading(true);
      const result = await apiLogin(email, password); // This calls the backend login
      
      if (result && result.error) {
        throw new Error(result.error);
      }
      
      // If login is successful, cookies should have been set by the server response
      // to apiLogin. Clear client-side caches. The subsequent hard redirect in
      // LoginForm.tsx will cause a new page load, and AuthProvider on that
      // page will perform a fresh auth check.
      authStore.clearAllCaches();
      
      return result;
    } catch (error) {
      console.error('Login failed:', error);
      // No need to call refreshAuth() on login failure here,
      // as auth state likely hasn't changed or is irrelevant to the failure.
      // The LoginForm will display the error.
      throw error;
    } finally {
      setIsLoading(false);
    }
  };
  
  const handleLogout = useCallback(async () => {
    try {
      setIsLoading(true);
      await apiLogout();
      router.push('/login');
    } catch (error) {
      console.error('Logout error:', error);
    } finally {
      setIsAuthenticated(false);
      setUser(null);
      setIsLoading(false);
    }
  }, [router, setIsLoading, setIsAuthenticated, setUser]); // Dependencies for handleLogout
  
  useEffect(() => {
    refreshAuth();
    
    // Set up a refresh interval (every 4 minutes)
    const interval = setInterval(() => {
      if (isAuthenticated) {
        refreshAuth();
      }
    }, 4 * 60 * 1000);
    
    // Add event listener for 401 errors
    const handle401 = async () => {
      // Call refreshAuth and get the latest status directly from its result
      const currentAuthStatus = await refreshAuth();
      
      // If still not authenticated after refresh attempt, redirect to login
      if (!currentAuthStatus.isAuthenticated) {
        router.push('/login');
      }
    };
    
    // Add event listener for logout events
    const handleLogoutEvent = (event: CustomEvent) => {
      console.log('Logout event received:', event.detail);
      handleLogout();
    };
    
    window.addEventListener('auth:401', handle401);
    window.addEventListener('auth:logout', handleLogoutEvent as EventListener);
    
    return () => {
      clearInterval(interval);
      window.removeEventListener('auth:401', handle401);
      window.removeEventListener('auth:logout', handleLogoutEvent as EventListener);
    };
  }, [isAuthenticated, router, refreshAuth, handleLogout]);
  
  return (
    <AuthContext.Provider
      value={{
        isAuthenticated,
        user,
        isLoading,
        refreshAuth,
        logout: handleLogout,
        login: handleLogin
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

