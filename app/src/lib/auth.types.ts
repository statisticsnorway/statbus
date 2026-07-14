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
  display_name: string;
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
  token_expires_at: string | null;
}

/**
 * Parses the raw JSON object from an auth RPC call (`login`, `logout`, `refresh`, `auth_status`)
 * into a well-typed AuthStatus object.
 *
 * @param rpcResponse - The raw data object from the PostgREST RPC response.
 * @returns A structured AuthStatus object.
 */
// The raw PostgREST RPC JSON shape (login / logout / refresh / auth_status). The
// user fields are present when is_authenticated is true; this typed cast is the
// external-boundary narrowing (replaces `any`).
type AuthStatusRpcResponse = {
  is_authenticated?: boolean;
  uid: number;
  sub: string;
  email: string;
  display_name: string;
  role: string;
  statbus_role: string;
  last_sign_in_at: string;
  created_at: string;
  expired_access_token_call_refresh?: boolean;
  error_code?: string | null;
  token_expires_at?: string | null;
};

export const _parseAuthStatusRpcResponseToAuthStatus = (rpcResponse: unknown): AuthStatus => {
  if (!rpcResponse) {
    return {
      isAuthenticated: false,
      user: null,
      expired_access_token_call_refresh: false,
      error_code: 'NULL_RPC_RESPONSE',
      token_expires_at: null,
    };
  }

  const r = rpcResponse as AuthStatusRpcResponse;
  const isAuthenticated = r.is_authenticated === true;
  const user: User | null = isAuthenticated
    ? {
        uid: r.uid,
        sub: r.sub,
        email: r.email,
        display_name: r.display_name,
        role: r.role,
        statbus_role: r.statbus_role,
        last_sign_in_at: r.last_sign_in_at,
        created_at: r.created_at,
      }
    : null;

  return {
    isAuthenticated,
    user,
    expired_access_token_call_refresh: r.expired_access_token_call_refresh === true,
    error_code: r.error_code || null,
    token_expires_at: r.token_expires_at || null,
  };
};
