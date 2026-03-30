import { statbusConfig } from "@/lib/statbus-config";

/**
 * Get the deployment slot code.
 * Used to namespace cookies for different environments.
 */
export function getDeploymentSlotCode(): string {
  if (typeof window !== 'undefined') {
    return statbusConfig.deploymentSlotCode || 'default';
  } else {
    return process.env.DEPLOYMENT_SLOT_CODE || 'default';
  }
}
