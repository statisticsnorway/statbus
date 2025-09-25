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
