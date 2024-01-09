import { toCamelCase, toPascalCase, createJsonReviver } from 'old/client/helpers/string'

describe('helpers/string: toCamelCase', () => {
  it('should transform string from pascal to camel case', () => {
    expect(toCamelCase('Qwe')).toBe('qwe')
  })

  it("shouldn't transform anything on empty string", () => {
    expect(toCamelCase('')).toBe('')
  })

  it("shouldn't transform string if its length is 1 char", () => {
    expect(toCamelCase('A')).toBe('A')
  })

  it("shouldn't transform string if it is undefined", () => {
    expect(toCamelCase(undefined)).toBe(undefined)
  })
})

describe('helpers/string: toPascalCase', () => {
  it('should transform string from pascal to camel case', () => {
    expect(toPascalCase('qwe')).toBe('Qwe')
  })

  it("shouldn't transform anything on empty string", () => {
    expect(toPascalCase('')).toBe('')
  })

  it("shouldn't transform string if its length is 1 char", () => {
    expect(toPascalCase('a')).toBe('a')
  })

  it("shouldn't transform string if it is undefined", () => {
    expect(toPascalCase(undefined)).toBe(undefined)
  })
})

describe('helpers/string: createJsonReviver', () => {
  it('should transform object properties from pascal case to camel case', () => {
    const camelCaseReviver = createJsonReviver(toCamelCase)
    const raw = JSON.stringify({ Value: 42 })
    expect(JSON.parse(raw, camelCaseReviver)).toEqual({ value: 42 })
  })

  it('should transform object properties from camel case to pascal case', () => {
    const pascalCaseReviver = createJsonReviver(toPascalCase)
    const raw = JSON.stringify({ value: 42 })
    expect(JSON.parse(raw, pascalCaseReviver)).toEqual({ Value: 42 })
  })
})
