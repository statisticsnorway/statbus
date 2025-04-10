"use client";

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { login as apiLogin, logout as apiLogout, refreshToken, getAuthStatus } from '@/services/auth';
import { fetchWithAuth } from '@/utils/auth/fetch-with-auth';

interface User {
  id: string;
  email: string;
  role: string;
  statbus_role: string;
}

interface AuthContextType {
  isAuthenticated: boolean;
  user: User | null;
  isLoading: boolean;
  refreshAuth: () => Promise<void>;
  logout: () => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  fetch: typeof fetchWithAuth;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  
  const refreshAuth = async () => {
    try {
      setIsLoading(true);
      
      // Get auth status from server
      try {
        const authStatus = await getAuthStatus();
        setIsAuthenticated(authStatus.isAuthenticated);
        setUser(authStatus.user);
        
        // If token is expiring soon, refresh it proactively
        if (authStatus.tokenExpiring) {
          await refreshToken();
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
  };
  
  const handleLogin = async (email: string, password: string) => {
    try {
      setIsLoading(true);
      const result = await apiLogin(email, password);
      if (result.error) {
        throw new Error(result.error);
      }
      await refreshAuth();
      return result;
    } finally {
      setIsLoading(false);
    }
  };
  
  const handleLogout = async () => {
    try {
      setIsLoading(true);
      await apiLogout();
    } finally {
      setIsAuthenticated(false);
      setUser(null);
      setIsLoading(false);
    }
  };
  
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
  }, [isAuthenticated]);
  
  return (
    <AuthContext.Provider
      value={{
        isAuthenticated,
        user,
        isLoading,
        refreshAuth,
        logout: handleLogout,
        login: handleLogin,
        fetch: fetchWithAuth
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuthContext() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuthContext must be used within an AuthProvider');
  }
  return context;
}
