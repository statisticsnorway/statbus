import {
  addClientCallback,
  handleWorkerStatusNotification,
  removeClientCallback,
  type NotificationData,
  type WorkerStatusPayload,
} from "./db-listener";

const progress = (completed: number): WorkerStatusPayload => ({
  type: "pipeline_progress",
  phases: [
    {
      phase: "is_deriving_statistical_units",
      step: "derive_statistical_unit",
      total: 3162,
      completed,
      effective_establishment_count: null,
      effective_legal_unit_count: 1000,
      effective_enterprise_count: null,
      effective_power_group_count: null,
    },
  ],
});

const completedOf = (data: NotificationData) =>
  data.channel === "worker_status" && "phases" in data.payload
    ? data.payload.phases[0].completed
    : null;

describe("worker_status relay", () => {
  const received: NotificationData[] = [];
  const callback = (data: NotificationData) => received.push(data);

  beforeEach(() => {
    jest.useFakeTimers();
    received.length = 0;
    addClientCallback("worker_status", callback);
  });

  afterEach(() => {
    removeClientCallback("worker_status", callback);
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  it("delivers the latest progress at least every 500 ms while notifications keep arriving", () => {
    // A recalculation completes refresh batches every ~130 ms (median gap measured
    // on a full-register run), so progress notifications arrive faster than 500 ms.
    for (let completed = 1; completed <= 50; completed++) {
      handleWorkerStatusNotification(progress(completed));
      jest.advanceTimersByTime(100);
    }

    // 5 s of arrivals: one delivery per 500 ms window, each carrying the newest count.
    expect(received.map(completedOf)).toEqual([5, 10, 15, 20, 25, 30, 35, 40, 45, 50]);
  });

  it("delivers the final state once arrivals stop", () => {
    handleWorkerStatusNotification(progress(1));
    jest.advanceTimersByTime(200);
    handleWorkerStatusNotification(progress(2));
    jest.advanceTimersByTime(500);

    expect(received.map(completedOf)).toEqual([2]);
  });

  it("delivers a phase's idle status after its last progress", () => {
    handleWorkerStatusNotification(progress(3162));
    handleWorkerStatusNotification({ type: "is_deriving_statistical_units", status: false });
    jest.advanceTimersByTime(500);

    expect(received.map((data) => data.payload)).toEqual([
      progress(3162),
      { type: "is_deriving_statistical_units", status: false },
    ]);
  });
});
