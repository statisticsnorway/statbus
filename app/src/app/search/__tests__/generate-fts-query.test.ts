import { generateFTSQuery } from "@/app/search/generate-fts-query";

describe("generateFTSQuery", () => {
  it("formats a simple query correctly", () => {
    const query = generateFTSQuery("car");
    expect(query).toEqual("'car':*");
  });

  it("formats a query with exclusions correctly", () => {
    const query = generateFTSQuery("car -racecar -toyota");
    expect(query).toEqual("'car':* & !'racecar':* & !'toyota':*");
  });

  it("formats a query with multiple included terms correctly", () => {
    const query = generateFTSQuery("electric car");
    expect(query).toEqual("'electric':* & 'car':*");
  });

  it("formats a query with leading whitespace correctly", () => {
    const query = generateFTSQuery(" electric car");
    expect(query).toEqual("'electric':* & 'car':*");
  });

  it("formats a query with trailing whitespace correctly", () => {
    const query = generateFTSQuery("electric car ");
    expect(query).toEqual("'electric':* & 'car':*");
  });

  it("formats a query with trailing exclusion symbol", () => {
    const query = generateFTSQuery("electric car -");
    expect(query).toEqual("'electric':* & 'car':*");
  });

  it("formats a query with conflicts in words", () => {
    const query = generateFTSQuery("electric -e");
    expect(query).toEqual("'electric':* & !'e':*");
  });

  it("formats a query with overlapping words", () => {
    const query = generateFTSQuery("te -tek");
    expect(query).toEqual("'te':* & !'tek':*");
  });

  it("formats a query with duplicate words", () => {
    const query = generateFTSQuery("electric -e -e");
    expect(query).toEqual("'electric':* & !'e':*");
  });

  it("formats a query from various prompt casing", () => {
    const query = generateFTSQuery("Electric -e -E");
    expect(query).toEqual("'electric':* & !'e':*");
  });

  it("formats a query without special chars such as &", () => {
    const query = generateFTSQuery("Bang & -Olufsen");
    expect(query).toEqual("'bang':* & !'olufsen':*");
  });

  it("supports queries containing unicode characters such as æ, ø and å", () => {
    const query = generateFTSQuery("Årseth");
    expect(query).toEqual("'årseth':*");
  });
});
