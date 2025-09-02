# A New Mindset: The Debugging Journal and Evidence-Based Intervention

## The Problem with Hubris

Past debugging efforts were hampered by a flawed methodology rooted in overconfidence. The repeated declaration of a "definitive fix" before conclusive evidence was gathered led to an inefficient, iterative process of "chipping away" at a complex problem. This approach was time-consuming, wasted significant resources, and ultimately failed to address the root cause at all, leaving the core problem unresolved. This document outlines the corrected, rigorous mindset and process for all future diagnostic work.

## Core Principles

### 1. Humility and Evidence-Based Experimentation

The core operating principle is now one of scientific humility. Every complex bug is treated as an unknown to be investigated, not a problem with an obvious solution.

-   **No "Fixes," Only Experiments:** I will no longer propose "fixes." Instead, I will propose *experiments* designed to test a specific, falsifiable hypothesis.
-   **Evidence is Paramount:** Every action must be aimed at gathering evidence. The first step in any investigation is to propose adding diagnostics (e.g., logging) to prove or disprove a hypothesis.
-   **Interventions are Experiments:** A code change intended to resolve a bug is simply another experiment. It must be accompanied by new diagnostics designed to prove whether the intervention was successful.
-   **Embrace Falsification:** A hypothesis can be wrong. The goal is to invalidate incorrect hypotheses as quickly as possible to narrow the search space and converge on the truth.

### 2. The Journal is Paramount

My context is not guaranteed to be persistent. It may be reset multiple times during a single debugging session. Therefore, maintaining a detailed, up-to-date investigation log in `app/tmp/journal.md` is not optional—it is the **most critical component** of this process. The journal is my memory. It ensures that progress is not lost and that I do not repeat failed experiments. It is the single source of truth for the investigation's state.

## The Methodology: Logical Elimination (Semantical Binary Search)

This mindset is implemented through a "semantical binary search" strategy. Its power lies in its efficiency at navigating complexity by systematically eliminating possibilities.

When faced with a complex system, guessing the single point of failure is a low-probability gamble. A binary search is ruthlessly efficient.

### The Process

A crucial refinement to this process is acknowledging that **multiple, interacting faults can exist simultaneously**. The process must therefore be exhaustive, but it must also be efficient. This is achieved by recursively halving the problem space.

1.  **Divide and Conquer:** Conceptually divide the system into two parts. The parts do not need to be of equal size. For a system with subsystems A, B, and C, a valid division is **Subsystem A** vs. **(Subsystems B + C)**.

2.  **Experiment by Isolation:** Test one half in isolation. For example, disable subsystems B and C to test A alone.
    *   **If the bug appears when only A is active:** This proves that Subsystem A contains a fault. A sub-investigation can begin within A to pinpoint that specific issue. However, this finding **does not** exonerate other subsystems. The overall problem may have multiple independent faults, so B and C must still be tested independently.
    *   **If the bug disappears when A is active alone:** This proves A is not faulty *in isolation*. The search space for the fault is now successfully reduced to the remaining subsystems (B, C) and their potential interactions.

3.  **Recurse and Repeat:** Continue the process on the remaining search space. If the fault is in (B + C):
    *   Divide again: **Subsystem B** vs. **Subsystem C**.
    *   Test B in isolation. If the bug appears, the fault is in B.
    *   If the bug does not appear, test C in isolation. If the bug appears, the fault is in C.

4.  **Test for Faulty Interactions:** If the bug does not appear when any subsystem (A, B, or C) is tested in isolation, but it *does* appear when they are all active, then the fault is an unstable **interaction** between them. The process is the same:
    *   Divide the *interactions* into halves. For interactions (A↔B), (A↔C), and (B↔C), a valid division is **(A↔B)** vs. **(A↔C + B↔C)**.
    *   Design an experiment to test the interaction. For example, enable A and B, but disable C, to test the A↔B interaction.
    *   Continue this process of elimination until the single faulty interaction is identified.

This exhaustive approach prevents premature declarations of victory and ensures that all contributing factors to a bug are identified and resolved. This is how I shall operate from now on.
