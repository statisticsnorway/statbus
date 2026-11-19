import { centreSquareCrop, UNIT_PHOTO_PIXELS } from "./unit-photo";

describe("centreSquareCrop", () => {
  it("takes the middle of a landscape phone photo", () => {
    expect(centreSquareCrop(4032, 3024)).toEqual({ sx: 504, sy: 0, side: 3024 });
  });

  it("takes the middle of a portrait photo", () => {
    expect(centreSquareCrop(3024, 4032)).toEqual({ sx: 0, sy: 504, side: 3024 });
  });

  it("keeps a square photo whole", () => {
    expect(centreSquareCrop(800, 800)).toEqual({ sx: 0, sy: 0, side: 800 });
  });

  it("stores photos at 512 pixels a side", () => {
    expect(UNIT_PHOTO_PIXELS).toBe(512);
  });
});
