/**
 * Render tests for the time-context chip's under-the-hood data attributes
 * (STATBUS-459).
 *
 * The app's Jest environment is node (no jsdom/testing-library), so the
 * component is rendered with renderToStaticMarkup and the `useTimeContext`
 * hook is mocked to seed the selected context. The attributes are asserted
 * to carry the exact selected ident + valid_on, and to be absent when there
 * is no selected context.
 */
import { renderToStaticMarkup } from "react-dom/server";
import TimeContextSelector from "./time-context-selector";
import { useTimeContext } from "@/atoms/app-derived";
import type { Tables } from "@/lib/database.types";

jest.mock("@/atoms/app-derived", () => ({
  useTimeContext: jest.fn(),
}));

const mockedUseTimeContext = jest.mocked(useTimeContext);

function makeTimeContext(
  overrides: Partial<Tables<"time_context">>,
): Tables<"time_context"> {
  return {
    type: "year",
    ident: "y_2023",
    name_when_query: "2023 (Data)",
    name_when_input: "2023",
    scope: "input_and_query",
    valid_from: "2023-01-01",
    valid_to: "2023-12-31",
    valid_on: "2023-12-31",
    code: null,
    path: null,
    ...overrides,
  };
}

function seedSelectedTimeContext(
  selectedTimeContext: Tables<"time_context"> | null,
): void {
  mockedUseTimeContext.mockReturnValue({
    selectedTimeContext,
    setSelectedTimeContext: jest.fn(),
    timeContexts: [],
    defaultTimeContext: null,
  });
}

test("the chip carries the selected context's ident and valid_on", () => {
  seedSelectedTimeContext(makeTimeContext({}));

  const html = renderToStaticMarkup(<TimeContextSelector />);

  expect(html).toContain('data-time-context-ident="y_2023"');
  expect(html).toContain('data-time-context-valid-on="2023-12-31"');
  // The visible label is unchanged.
  expect(html).toContain("2023 (Data)");
});

test("the attributes follow the selected context value", () => {
  seedSelectedTimeContext(
    makeTimeContext({
      ident: "y_2019",
      name_when_query: "2019 (Data)",
      valid_on: "2019-12-31",
    }),
  );

  const html = renderToStaticMarkup(<TimeContextSelector />);

  expect(html).toContain('data-time-context-ident="y_2019"');
  expect(html).toContain('data-time-context-valid-on="2019-12-31"');
  expect(html).not.toContain("y_2023");
});

test("neither attribute is present when no context is selected", () => {
  seedSelectedTimeContext(null);

  const html = renderToStaticMarkup(<TimeContextSelector />);

  expect(html).not.toContain("data-time-context-ident");
  expect(html).not.toContain("data-time-context-valid-on");
  // Falls back to the provided title, as before.
  expect(html).toContain("Select time");
});
