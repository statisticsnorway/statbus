import { generateFTSQuery } from "@/app/search/generate-fts-query";

describe("generateFTSQuery", () => {
  const testCases = [
    ["car", "'car':*"],
    ["car -racecar -toyota", "'car':* & !'racecar':* & !'toyota':*"],
    ["electric car", "'electric':* & 'car':*"],
    [" electric car", "'electric':* & 'car':*"],
    ["electric car ", "'electric':* & 'car':*"],
    ["electric car -", "'electric':* & 'car':*"],
    ["electric -e", "'electric':* & !'e':*"],
    ["te -tek", "'te':* & !'tek':*"],
    ["electric -e -e", "'electric':* & !'e':*"],
    ["Electric -e -E", "'electric':* & !'e':*"],
    ["Bang & -Olufsen", "'bang':* & !'olufsen':*"],
    ["Årseth", "'årseth':*"],
  ];

  testCases.forEach(([input, expected]) => {
    it(`should return ${expected} for input "${input}"`, () => {
      const query = generateFTSQuery(input);
      expect(query).toEqual(expected);
    });
  });
});
