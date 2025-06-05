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
  
  const refreshAuth = useCallback(async () => {
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
    } finally {
      setIsLoading(false);
    }
  }, [setIsLoading, setIsAuthenticated, setUser]); // Dependencies for refreshAuth
  
  const handleLogin = async (email: string, password: string) => {
    try {
      setIsLoading(true);
      const result = await apiLogin(email, password);
      
      if (result && result.error) {
        throw new Error(result.error);
      }
      
      // Update auth state after successful login
      await refreshAuth();
      return result;
    } catch (error) {
      console.error('Login failed:', error);
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
      await refreshAuth();
      
      // If still not authenticated after refresh attempt, redirect to login
      if (!isAuthenticated) {
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

