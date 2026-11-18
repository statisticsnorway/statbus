/**
 * 50bwaz: the custom activity code upload needs the activity category
 * standard from step 2; codes are checked against it. Without it the page
 * sends the user to step 2 instead of an upload the database refuses
 * ("Missing public.settings.activity_category_standard_id", North Cyprus
 * 2026-11-18).
 */
import { renderToStaticMarkup } from "react-dom/server";
import { RequiresActivityStandard } from "./requires-activity-standard";

describe("RequiresActivityStandard", () => {
  it("sends the user to step 2 when no activity category standard is set", () => {
    const html = renderToStaticMarkup(
      <RequiresActivityStandard settings={null}>
        <p>upload form</p>
      </RequiresActivityStandard>
    );
    expect(html).toContain("Select the activity category standard in step 2 first");
    expect(html).toContain('href="/getting-started/activity-standard"');
    expect(html).not.toContain("upload form");
  });

  it("shows the upload once a standard is set", () => {
    const html = renderToStaticMarkup(
      <RequiresActivityStandard settings={{ activity_category_standard: { id: 2, name: "NACE 2.1" } }}>
        <p>upload form</p>
      </RequiresActivityStandard>
    );
    expect(html).toContain("upload form");
    expect(html).not.toContain("step 2 first");
  });
});
