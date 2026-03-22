const MODE_UPLOAD_PATHS: Record<string, string> = {
  legal_unit: '/import/legal-units/upload',
  establishment_formal: '/import/establishments/upload',
  establishment_informal: '/import/establishments-without-legal-unit/upload',
  legal_relationship: '/import/upload',
};

export function getUploadPath(mode: string, jobSlug: string): string {
  return `${MODE_UPLOAD_PATHS[mode] ?? '/import/upload'}/${jobSlug}`;
}
