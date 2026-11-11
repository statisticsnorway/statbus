/**
 * STATBUS-619: an admin dialog's Save shows that it is working. On Norway a
 * statistical variable save takes 9 to 13 s; the dialog showed nothing, so the
 * user pressed Save again. Rendered statically (node environment).
 */
import { renderToStaticMarkup } from "react-dom/server";
import { AdminDialogFooter } from "./admin-dialog-footer";

jest.mock("@/components/ui/dialog", () => ({
  DialogFooter: ({ children }: { children: React.ReactNode }) => <div data-footer>{children}</div>,
  DialogClose: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

describe("AdminDialogFooter", () => {
  it("offers Cancel and the submit label while idle", () => {
    const html = renderToStaticMarkup(<AdminDialogFooter submitLabel="Save changes" pending={false} state={null} />);
    expect(html).toContain(">Cancel<");
    expect(html).toMatch(/<button[^>]*type="submit"[^>]*>Save changes<\/button>/);
    expect(html).not.toMatch(/<button[^>]*type="submit"[^>]*disabled/);
  });

  it("disables both buttons and reads Saving… while the save runs", () => {
    const html = renderToStaticMarkup(<AdminDialogFooter submitLabel="Save changes" pending state={null} />);
    expect(html).toMatch(/<button[^>]*type="submit"[^>]*disabled[^>]*>.*Saving…<\/button>/);
    expect(html).toMatch(/<button[^>]*disabled[^>]*>Cancel<\/button>/);
  });

  it("shows the server's error message once the save has failed", () => {
    const html = renderToStaticMarkup(
      <AdminDialogFooter submitLabel="Create" pending={false} state={{ status: "error", message: "duplicate key value" }} />
    );
    expect(html).toContain('role="alert"');
    expect(html).toContain("duplicate key value");
  });
});
