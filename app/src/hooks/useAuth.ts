import { useContext } from 'react';
import { AuthContext } from '@/context/AuthContext';

/**
 * Hook to access the authentication context
 * Provides authentication state and methods throughout the application
 */
export function useAuth() {
  const context = useContext(AuthContext);
  
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  
  return context;
}
