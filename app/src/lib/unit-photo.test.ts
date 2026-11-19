import {
  fitWithin,
  UNIT_PHOTO_MAX_BYTES,
  UNIT_PHOTO_MAX_SIDE,
} from "./unit-photo";

describe("fitWithin", () => {
  it("scales a landscape phone photo to 800 px wide, keeping all of it", () => {
    expect(fitWithin(4032, 3024, UNIT_PHOTO_MAX_SIDE)).toEqual({
      width: 800,
      height: 600,
    });
  });

  it("scales a portrait photo to 800 px high", () => {
    expect(fitWithin(3024, 4032, UNIT_PHOTO_MAX_SIDE)).toEqual({
      width: 600,
      height: 800,
    });
  });

  it("leaves a photo that already fits at its own size", () => {
    expect(fitWithin(640, 480, UNIT_PHOTO_MAX_SIDE)).toEqual({
      width: 640,
      height: 480,
    });
  });

  it("keeps photos under the database limit of 256 KB", () => {
    expect(UNIT_PHOTO_MAX_BYTES).toBe(262144);
  });
});
