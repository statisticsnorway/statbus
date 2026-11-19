/**
 * m6mnnw: a unit edit form shows that its save is running. On Norway a save
 * waits for the recalculation, seconds with nothing to see, so a user clicked
 * Save again or left. While the form's action runs, Save reads "Saving…" with a
 * spinner and Save and Cancel are disabled, in the field group (general info,
 * contact, demographic) and in the single fields.
 *
 * The app's Jest environment is node, so the forms are rendered with
 * renderToStaticMarkup, in the editing state, with the form's status
 * (useFormStatus) given by the test: pending or idle.
 */
import { renderToStaticMarkup } from "react-dom/server";

let formPending = false;
jest.mock("react-dom", () => ({
  ...jest.requireActual("react-dom"),
  useFormStatus: () => ({ pending: formPending, data: null, method: null, action: null }),
}));

jest.mock("@/atoms/edits", () => ({
  useEditManager: () => ({
    currentEdit: { fieldId: "general-info", removing: null },
    setEditTarget: () => {},
    exitEditMode: () => {},
  }),
}));
jest.mock("./use-start-edit", () => ({ useStartEdit: () => () => {} }));
jest.mock("./use-edit-anchor", () => ({ useEditAnchor: () => ({ values: null }) }));
jest.mock("./edit-metadata-controls", () => ({
  EditMetadataControls: () => null,
  SaveApproval: () => null,
  useSaveApproval: () => ({ blocked: false, count: 0 }),
}));
jest.mock("./primary-unit-notice", () => ({ PrimaryUnitNotice: () => null }));
jest.mock("./remove-record-button", () => ({ RemoveRecordAction: () => null }));
jest.mock("./field-timeline-view", () => ({ FieldTimelineButton: () => null }));
jest.mock("./metadata-tooltip", () => ({ MetadataTooltip: () => null }));
jest.mock("./submission-feedback-debug-info", () => ({ SubmissionFeedbackDebugInfo: () => null }));

import { EditableFieldGroup } from "./editable-field-group";
import { EditableField } from "./editable-field";

const noop = () => {};

function group() {
  return renderToStaticMarkup(
    <EditableFieldGroup fieldGroupId="general-info" title="General info" action={noop} response={null}>
      {() => <input name="name" defaultValue="Veridit AS" />}
    </EditableFieldGroup>
  );
}

function field() {
  return renderToStaticMarkup(
    <EditableField fieldId="general-info" label="Name" value="Veridit AS" formAction={noop} response={null} />
  );
}

// The disabled attribute (disabled=""), not the disabled: variants in the class list.
const saving = /<button[^>]*\sdisabled=""[^>]*>.*Saving…<\/button>/;
const cancelDisabled = /<button[^>]*\sdisabled=""[^>]*>Cancel<\/button>/;

describe.each([
  ["the field group", group],
  ["a single field", field],
])("%s while editing", (_name, render) => {
  it("offers Save and an enabled Cancel while no save runs", () => {
    formPending = false;
    const html = render();
    expect(html).toMatch(/>Save<\/button>/);
    expect(html).not.toContain("Saving…");
    expect(html).not.toMatch(cancelDisabled);
  });

  it("reads Saving… with Save and Cancel disabled while the save runs", () => {
    formPending = true;
    const html = render();
    expect(html).toMatch(saving);
    expect(html).toMatch(cancelDisabled);
  });
});
