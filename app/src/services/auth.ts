import { getDeploymentSlotCode } from '@/utils/auth/jwt';

/**
 * Authentication service for direct interaction with the PostgREST API
 */

/**
 * Get the current authentication status from the server
 */
export async function getAuthStatus() {
  const response = await fetch('/api/rpc/auth_status', {
    method: 'POST',
    credentials: 'include'
  });
  
  return response.json();
}

/**
 * Login with email and password
 * This calls the PostgreSQL login function directly via PostgREST
 */
export async function login(email: string, password: string) {
  const response = await fetch('/api/rpc/login', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ email, password }),
    credentials: 'include' // Important for cookies
  });
  
  return response.json();
}

/**
 * Logout the current user
 * This calls the PostgreSQL logout function directly via PostgREST
 */
export async function logout() {
  const response = await fetch('/api/rpc/logout', {
    method: 'POST',
    credentials: 'include'
  });
  
  return response.json();
}

/**
 * Refresh the authentication token
 * This calls the PostgreSQL refresh function directly via PostgREST
 */
export async function refreshToken() {
  const response = await fetch('/api/rpc/refresh', {
    method: 'POST',
    credentials: 'include'
  });
  
  return response.json();
}

/**
 * List all active sessions for the current user
 */
export async function listActiveSessions() {
  const response = await fetch('/api/rpc/list_active_sessions', {
    method: 'POST',
    credentials: 'include'
  });
  
  return response.json();
}

/**
 * Revoke a specific session
 */
export async function revokeSession(sessionId: string) {
  const response = await fetch('/api/rpc/revoke_session', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ refresh_session_jti: sessionId }),
    credentials: 'include'
  });
  
  return response.json();
}
