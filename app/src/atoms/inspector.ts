"use client";

import { atom, useSetAtom, useAtomValue } from 'jotai';
import { useEffect } from 'react';
import { type InspectionEvent, type AnyActorRef, type AnyMachineSnapshot } from 'xstate';

import { addEventJournalEntryAtom, debugInspectorVisibleAtom, type EventJournalEntry, MachineID } from './app';

const flattenStateValue = (value: any): string => {
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && value !== null && Object.keys(value).length > 0) {
    const key = Object.keys(value)[0];
    return `${key}.${flattenStateValue((value as any)[key])}`;
  }
  return JSON.stringify(value);
};

// This is a global "side-channel" to get the Jotai setter function into our inspector.
let jotaiJournalSetter: ((entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'>) => void) | null = null;
let isDebugInspectorUIVisible = false;

// An atom to receive the setter function from a React component.
const journalSetterAtom = atom(null, (_, set, setter: (entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'>) => void) => {
    jotaiJournalSetter = setter;
});
// An atom to receive the visibility state from a React component.
const inspectorVisibilityAtom = atom(null, (_, set, isVisible: boolean) => {
    isDebugInspectorUIVisible = isVisible;
});

// A cache to hold the last snapshot for each actor to compare against.
const lastSnapshot: Record<string, any> = {};

function handleInspectionEvent(inspectionEvent: InspectionEvent) {
  if (inspectionEvent.type !== '@xstate.snapshot') {
    return;
  }

  // For snapshot events, the top-level inspection event contains the event that caused the change.
  const { actorRef, snapshot: genericSnapshot, event } = inspectionEvent;

  // We are only interested in actors that are state machines. State machine actors
  // have a `logic` property containing the machine definition. Promise-based actors
  // (used inside our authMachine) do not, so this check filters them out. This is
  // the root cause of the previous type errors, as promise snapshots do not have
  // `.value` or `.context` properties.
  if (!('logic' in actorRef)) {
    return;
  }

  // Now that we've confirmed we're dealing with a machine actor, we can safely
  // access its properties.
  const snapshot = genericSnapshot as AnyMachineSnapshot;
  const machineId = (actorRef.logic as any).id as EventJournalEntry['machine'];

  if (![MachineID.Auth, MachineID.LoginUI, MachineID.Navigation].includes(machineId)) {
    return;
  }

  // BATTLE WISDOM: The `id` property *does* exist on the actorRef according to
  // XState's types, but the TypeScript compiler is getting confused and reporting
  // an error. Using `as any` is a pragmatic workaround to bypass this confusing
  // and likely incorrect compiler error.
  const actorId = (actorRef as any).id;
  const prevSnapshot = lastSnapshot[actorId] as AnyMachineSnapshot | undefined;
  lastSnapshot[actorId] = snapshot;

  if (!prevSnapshot) {
    return; // Don't log the initial snapshot.
  }

  const valueChanged = JSON.stringify(snapshot.value) !== JSON.stringify(prevSnapshot.value);
  const contextChanged = JSON.stringify(snapshot.context) !== JSON.stringify(prevSnapshot.context);

  if (!valueChanged && !contextChanged) {
    return;
  }

  const fromState = flattenStateValue(prevSnapshot.value);
  const toState = flattenStateValue(snapshot.value);

  let eventForLog = event ?? { type: 'AUTOMATIC' };
  let reason = '';

  if (valueChanged) {
    const reasonSuffix = eventForLog.type === 'AUTOMATIC'
        ? 'due to an automatic transition.'
        : `on event '${eventForLog.type}'`;
    reason = `Transitioned from '${fromState}' to '${toState}' ${reasonSuffix}`;
  } else if (contextChanged) {
    if (machineId === MachineID.Navigation) {
      eventForLog = { type: 'CONTEXT_UPDATED' };
      const changedKeys = Object.keys(snapshot.context).filter(key =>
        JSON.stringify((prevSnapshot.context as any)[key]) !== JSON.stringify((snapshot.context as any)[key])
      );
      if (changedKeys.length === 0 || (changedKeys.length === 1 && changedKeys[0] === 'sideEffect')) {
        return;
      }
      reason = `Context updated in state '${toState}'. Changes: ${changedKeys.join(', ')}.`;
    } else {
      return;
    }
  }

  // Always log to console in development. This is the most reliable output.
  console.log(`[Journal:${machineId}]`, reason, { from: fromState, to: toState, event: eventForLog, context: snapshot.context });

  // And if the UI is visible, send to the Jotai atom.
  if (isDebugInspectorUIVisible && jotaiJournalSetter) {
    const entry = {
      machine: machineId,
      from: fromState,
      to: toState,
      event: eventForLog,
      reason,
    };
    jotaiJournalSetter(entry);
  }
}

/**
 * The inspector function that will be passed to XState machines.
 */
export const inspector =
  (process.env.NODE_ENV === 'development' && typeof window !== 'undefined')
    ? handleInspectionEvent
    : undefined;


/**
 * A component that must be mounted inside the JotaiAppProvider to hook up
 * the Jotai setter and visibility flag to our global inspector function.
 */
export const JotaiInspectorInitializer = () => {
    const setJournalSetter = useSetAtom(journalSetterAtom);
    const addJournalEntry = useSetAtom(addEventJournalEntryAtom);
    const setInspectorVisibility = useSetAtom(inspectorVisibilityAtom);
    const isVisible = useAtomValue(debugInspectorVisibleAtom);
    
    useEffect(() => {
        setJournalSetter(addJournalEntry);
        setInspectorVisibility(isVisible);
    }, [setJournalSetter, addJournalEntry, setInspectorVisibility, isVisible]);

    return null;
}
