/**
 * Get the deployment slot code
 * This is used to namespace cookies for different environments
 */
export function getDeploymentSlotCode(): string {
  if (typeof window !== 'undefined') {
    // Client-side
    // Try to get from environment variable first (exposed to client)
    if (process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE) {
      return process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE;
    }
    
    // Fallback to default
    return 'default';
  } else {
    // Server-side
    return process.env.DEPLOYMENT_SLOT_CODE || 'default';
  }
}

/**
 * Check if a JWT token is expired based on its expiration claim
 * This doesn't verify the signature, just checks the expiration time
 */
export function isTokenExpired(token: string): boolean {
  try {
    // Extract the payload without verifying the signature
    const parts = token.split('.');
    if (parts.length !== 3) {
      return true;
    }
    
    // Decode the payload
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    
    // Check if token is expired
    const now = Math.floor(Date.now() / 1000);
    return payload.exp <= now;
  } catch (error) {
    // If there's any error parsing the token, consider it expired
    return true;
  }
}
