export default function persist(syntheticEvent) {
  if (syntheticEvent !== undefined && typeof syntheticEvent.persist === 'function') {
    syntheticEvent.persist()
  }
  return syntheticEvent
}
