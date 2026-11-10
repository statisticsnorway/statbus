/**
 * Render tests for the time-frame chip and menu (STATBUS-459, STATBUS-606).
 *
 * The app's Jest environment is node (no jsdom/testing-library), so the
 * component is rendered with renderToStaticMarkup and the `useTimeFrame`
 * hook is mocked to seed the frames. The chip carries the selected frame's
 * ident + valid_on, and the menu lists the frames under their kind headings.
 */
import { renderToStaticMarkup } from "react-dom/server";
import TimeFrameSelector from "./time-frame-selector";
import { useTimeFrame } from "@/atoms/app-derived";
import type { Tables } from "@/lib/database.types";

jest.mock("@/atoms/app-derived", () => ({
  useTimeFrame: jest.fn(),
}));

// Render the popover content inline so the menu appears in static markup.
jest.mock("@/components/ui/popover", () => ({
  Popover: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PopoverTrigger: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PopoverContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const mockedUseTimeFrame = jest.mocked(useTimeFrame);

type TimeFrameRow = Tables<"time_frame">;

function makeTimeFrame(overrides: Partial<TimeFrameRow>): TimeFrameRow {
  return {
    ident: "y_2023",
    kind: "fixed",
    name: "Frame 2023",
    valid_from: "2023-01-01",
    valid_to: "2023-12-31",
    valid_on: "2023-12-31",
    year: 2023,
    equals_frame_ident: null,
    ...overrides,
  };
}

const live = makeTimeFrame({
  ident: "live",
  kind: "live",
  name: "Live frame",
  valid_from: "2026-01-01",
  valid_to: "infinity",
  valid_on: "2026-11-10",
  year: null,
});
const previous = makeTimeFrame({
  ident: "r_previous",
  kind: "relative",
  name: "Previous frame",
  valid_from: "2025-01-01",
  valid_to: "2025-12-31",
  valid_on: "2025-12-31",
  year: 2025,
});
const fixed2025 = makeTimeFrame({
  ident: "y_2025",
  name: "Frame 2025",
  valid_from: "2025-01-01",
  valid_to: "2025-12-31",
  valid_on: "2025-12-31",
  year: 2025,
  equals_frame_ident: "r_previous",
});
const fixed2023 = makeTimeFrame({});

function seed(
  selectedTimeFrame: TimeFrameRow | null,
  timeFrames: TimeFrameRow[] = [],
): void {
  mockedUseTimeFrame.mockReturnValue({
    selectedTimeFrame,
    setSelectedTimeFrame: jest.fn(),
    timeFrames,
    defaultTimeFrame: timeFrames[0] ?? null,
  } as unknown as ReturnType<typeof useTimeFrame>);
}

test("the chip carries the selected frame's ident, valid_on and name", () => {
  seed(fixed2023);

  const html = renderToStaticMarkup(<TimeFrameSelector />);

  expect(html).toContain('data-time-frame-ident="y_2023"');
  expect(html).toContain('data-time-frame-valid-on="2023-12-31"');
  expect(html).toContain("Frame 2023");
});

test("neither attribute is present when no frame is selected", () => {
  seed(null);

  const html = renderToStaticMarkup(<TimeFrameSelector />);

  expect(html).not.toContain("data-time-frame-ident");
  expect(html).not.toContain("data-time-frame-valid-on");
  expect(html).toContain("Select time frame");
});

test("the menu groups frames by kind and omits a fixed frame equal to a relative one", () => {
  seed(live, [live, previous, fixed2025, fixed2023]);

  const html = renderToStaticMarkup(<TimeFrameSelector />);

  const liveAt = html.indexOf("Live frame");
  const relativeAt = html.indexOf("Relative frames");
  const fixedAt = html.indexOf("Fixed frames");
  expect(liveAt).toBeGreaterThanOrEqual(0);
  expect(relativeAt).toBeGreaterThan(liveAt);
  expect(fixedAt).toBeGreaterThan(relativeAt);
  expect(html.indexOf("Previous frame")).toBeGreaterThan(relativeAt);
  expect(html.indexOf("Frame 2023")).toBeGreaterThan(fixedAt);
  expect(html).not.toContain("Frame 2025");
});
