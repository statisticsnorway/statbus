/**
 * The Time frame panel's views (owner 2026-11-13): Frame and Timeline, where
 * Simple and Advanced were. The Frame view is one menu: the time frames, then
 * "Specific dates…" (From and To appear below it) and, on an import whose file
 * dates its rows, "Dates from the file". Without a timeline (an import) there
 * is only the Frame view, so no view switch.
 *
 * The app's Jest environment is node, so the panel is rendered with
 * renderToStaticMarkup and the Radix select is rendered inline.
 */
import { renderToStaticMarkup } from "react-dom/server";
import { TimeFramePanel, type TimeFramePanelProps } from "./time-frame-panel";
import type { TimeFrame } from "@/lib/time-frame";

jest.mock("@/components/ui/select", () => {
  const Pass = ({ children }: { children?: React.ReactNode }) => <div>{children}</div>;
  return {
    Select: Pass,
    SelectContent: Pass,
    SelectGroup: Pass,
    SelectLabel: Pass,
    SelectTrigger: Pass,
    SelectValue: () => null,
    SelectSeparator: () => <hr />,
    SelectItem: ({ value, children }: { value: string; children?: React.ReactNode }) => (
      <div data-option={value}>{children}</div>
    ),
  };
});

const frames = [
  { ident: "live", kind: "live", name: "Live frame (2026)", valid_from: "2026-01-01", valid_to: "infinity", valid_on: "2026-11-13", year: null, equals_frame_ident: null },
  { ident: "prev", kind: "relative", name: "Previous frame (2025)", valid_from: "2025-01-01", valid_to: "2025-12-31", valid_on: "2025-12-31", year: 2025, equals_frame_ident: null },
] as unknown as TimeFrame[];

const noop = () => {};
function render(overrides: Partial<TimeFramePanelProps>) {
  return renderToStaticMarkup(
    <TimeFramePanel
      idPrefix="t"
      timeFrames={frames}
      mode="frame"
      onModeChange={noop}
      choice="frame"
      onChoiceChange={noop}
      frameIdent="live"
      onFrameChange={noop}
      validFrom="2026-01-01"
      validTo={null}
      onValidFromChange={noop}
      onValidToChange={noop}
      dataSources={[]}
      dataSourceCode={null}
      onDataSourceChange={noop}
      comment={null}
      onCommentChange={noop}
      {...overrides}
    />
  );
}

const views = (html: string) => [...html.matchAll(/data-time-frame-mode="(\w+)"/g)].map((m) => m[1]);
// The Frame menu's options; the Data source list ("__none__" and the sources) follows it.
const frameOptions = (html: string) =>
  [...html.matchAll(/data-option="([^"]+)"/g)].map((m) => m[1]).filter((v) => v !== "__none__");

describe("TimeFramePanel views", () => {
  it("offers Frame and Timeline for an edit with a timeline", () => {
    const html = render({ timeline: <p>timeline</p> });
    expect(views(html)).toEqual(["frame", "timeline"]);
    expect(html).toContain(">Frame<");
    expect(html).toContain(">Timeline<");
  });

  it("has no view switch without a timeline (an import)", () => {
    expect(views(render({}))).toEqual([]);
  });

  it("lists the frames, then Specific dates, in the Frame menu", () => {
    expect(frameOptions(render({}))).toEqual(["live", "prev", "__dates__"]);
  });

  it("offers the file's own dates on an import that has them", () => {
    const html = render({ sourceDates: { label: "Source dates", description: "Each row's valid_from and valid_to." } });
    expect(frameOptions(html)).toEqual(["live", "prev", "__dates__", "__source_dates__"]);
  });

  it("shows From and To below the menu when Specific dates is chosen, not before", () => {
    expect(render({})).not.toContain('aria-label="From"');
    const html = render({ choice: "dates", validFrom: "2024-03-01" });
    expect(html).toContain('aria-label="From"');
    expect(html).toContain('aria-label="To"');
  });
});
