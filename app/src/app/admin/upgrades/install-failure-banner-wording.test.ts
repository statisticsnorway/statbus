import { INSTALL_FAILURE_BANNER_WORDING } from "./install-failure-banner";

test("provisional install failure banner wording", () => {
  expect(INSTALL_FAILURE_BANNER_WORDING).toBe(
    "The last installation did not finish. Run the installer again. This message clears after a successful installation or upgrade."
  );
});
