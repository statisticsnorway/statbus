import fn from 'old/client/helpers/queryObjectToString'

describe('helpers/queryObjectToString', () => {
  [
    ['should parse empty object to empty string', {}, ''],
    ['should parse one-key object to valid query string', { a: 1 }, '?a=1'],
    [
      'should parse array to valid query string (repeate array name on each occurence)',
      { a: [1, 2] },
      '?a=1&a=2',
    ],
    [
      'should parse nested object to valid query string (dot-separated path as names)',
      { a: { b: 42 } },
      '?a.b=42',
    ],
    [
      'should parse object with mixed props (plain, array, nested object) to valid query string',
      { a: { b: 42 }, c: [1, 'two', 3], d: 17 },
      '?a.b=42&c=1&c=two&c=3&d=17',
    ],
  ].forEach(([text, input, expected]) => it(text, () => expect(fn(input)).toBe(expected)))
})
