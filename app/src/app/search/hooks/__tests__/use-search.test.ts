import {generateFTSQuery} from "@/app/search/hooks/use-search";

describe("generateFTSQuery", () => {
  it('formats a simple query correctly', () => {
    const query = generateFTSQuery('car');
    expect(query).toEqual("fts(simple).'car':*");
  });

  it('formats a query with exclusions correctly', () => {
    const query = generateFTSQuery('car -racecar -toyota');
    expect(query).toEqual("fts(simple).'car':* & !'racecar':* & !'toyota':*");
  });

  it('formats a query with multiple included terms correctly', () => {
    const query = generateFTSQuery('electric car');
    expect(query).toEqual("fts(simple).'electric':* & 'car':*");
  });

  it('formats a query with leading whitespace correctly', () => {
    const query = generateFTSQuery(' electric car');
    expect(query).toEqual("fts(simple).'electric':* & 'car':*");
  });

  it('formats a query with trailing whitespace correctly', () => {
    const query = generateFTSQuery('electric car ');
    expect(query).toEqual("fts(simple).'electric':* & 'car':*");
  });

  it('formats a query with trailing exclusion symbol', () => {
    const query = generateFTSQuery('electric car -');
    expect(query).toEqual("fts(simple).'electric':* & 'car':*");
  });

  it('formats a query with conflicts in words', () => {
    const query = generateFTSQuery('electric -e');
    expect(query).toEqual("fts(simple).'electric':* & !'e':*");
  });

  it('formats a query with overlapping words', () => {
    const query = generateFTSQuery('te -tek');
    expect(query).toEqual("fts(simple).'te':* & !'tek':*");
  });

  it('formats a query with duplicate words', () => {
    const query = generateFTSQuery('electric -e -e');
    expect(query).toEqual("fts(simple).'electric':* & !'e':*");
  });

  it('formats a query from various prompt casing', () => {
    const query = generateFTSQuery('Electric -e -E');
    expect(query).toEqual("fts(simple).'electric':* & !'e':*");
  });

  it('formats a query without special chars such as &', () => {
    const query = generateFTSQuery('Bang & -Olufsen');
    expect(query).toEqual("fts(simple).'bang':* & !'olufsen':*");
  });
})
