import { type EventJournalEntry } from './app';

const flattenStateValue = (value: any): string => {
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && value !== null && Object.keys(value).length > 0) {
    const key = Object.keys(value)[0];
    return `${key}.${flattenStateValue((value as any)[key])}`;
  }
  return JSON.stringify(value);
};

export function createJournalEntry(
  prevSnapshot: any,
  currentSnapshot: any,
  machine: EventJournalEntry['machine']
): Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'> | null {
  const valueChanged = JSON.stringify(currentSnapshot.value) !== JSON.stringify(prevSnapshot.value);
  const contextChanged = JSON.stringify(currentSnapshot.context) !== JSON.stringify(prevSnapshot.context);

  if (!valueChanged && !contextChanged) {
    return null;
  }

  const fromState = flattenStateValue(prevSnapshot.value);
  const toState = flattenStateValue(currentSnapshot.value);

  const rawEvent = (currentSnapshot as any).event;
  let eventForLog = rawEvent && rawEvent.type ? rawEvent : { type: 'AUTOMATIC' };
  let reason = '';

  if (valueChanged) {
    const reasonSuffix = eventForLog.type === 'AUTOMATIC'
        ? 'due to an automatic transition.'
        : `on event '${eventForLog.type}'`;
    reason = `Transitioned from '${fromState}' to '${toState}' ${reasonSuffix}`;
  } else if (contextChanged) {
    // For the navigation machine, a context-only change is a specific event.
    if (machine === 'nav') {
      eventForLog = { type: 'CONTEXT_UPDATED' };
      const changedKeys = Object.keys(currentSnapshot.context).filter(key =>
        JSON.stringify((prevSnapshot.context as any)[key]) !== JSON.stringify((currentSnapshot.context as any)[key])
      );
      // Ignore internal-only context changes that aren't meaningful to the user.
      if (changedKeys.length === 0 || (changedKeys.length === 1 && changedKeys[0] === 'sideEffect')) {
        return null;
      }
      reason = `Context updated in state '${toState}'. Changes: ${changedKeys.join(', ')}.`;
    } else {
      // Other machines do not currently have meaningful context-only transitions to log.
      // We can add generic handling here if needed in the future.
      return null;
    }
  }

  return {
    machine,
    from: fromState,
    to: toState,
    event: eventForLog,
    reason,
  };
}
