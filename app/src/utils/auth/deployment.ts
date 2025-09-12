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
