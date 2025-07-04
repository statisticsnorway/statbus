// This file contains types and utility functions related to authentication
// that are shared between server-side and client-side code.
// It MUST NOT contain any "use client" directive or client-specific code.

/**
 * User type definition for authentication
 */
export interface User {
  uid: number;
  sub: string;
  email: string;
  role: string;
  statbus_role: string;
  last_sign_in_at: string;
  created_at: string;
}

/**
 * Authentication status type
 */
export interface AuthStatus {
  isAuthenticated: boolean;
  expired_access_token_call_refresh: boolean;
  user: User | null;
  error_code: string | null;
}

/**
 * Parses the raw JSON object from an auth RPC call (`login`, `logout`, `refresh`, `auth_status`)
 * into a well-typed AuthStatus object.
 *
 * @param rpcResponse - The raw data object from the PostgREST RPC response.
 * @returns A structured AuthStatus object.
 */
export const _parseAuthStatusRpcResponseToAuthStatus = (rpcResponse: any): AuthStatus => {
  if (!rpcResponse) {
    return {
      isAuthenticated: false,
      user: null,
      expired_access_token_call_refresh: false,
      error_code: 'NULL_RPC_RESPONSE',
    };
  }

  const isAuthenticated = rpcResponse.is_authenticated === true;
  const user: User | null = isAuthenticated
    ? {
        uid: rpcResponse.uid,
        sub: rpcResponse.sub,
        email: rpcResponse.email,
        role: rpcResponse.role,
        statbus_role: rpcResponse.statbus_role,
        last_sign_in_at: rpcResponse.last_sign_in_at,
        created_at: rpcResponse.created_at,
      }
    : null;

  return {
    isAuthenticated,
    user,
    expired_access_token_call_refresh: rpcResponse.expired_access_token_call_refresh === true,
    error_code: rpcResponse.error_code || null,
  };
};
