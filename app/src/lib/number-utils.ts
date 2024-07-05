export function thousandSeparator(value: number | string | null | undefined) {
  return value?.toString().replace(/\B(?=(\d{3})+(?!\d))/g, "\u00a0");
}
