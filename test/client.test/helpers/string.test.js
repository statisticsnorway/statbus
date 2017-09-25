import { toCamelCase, toPascalCase } from 'client/helpers/string'

describe('helpers/string: pascal case to camel case', () => {

  it('should transform string from pascal to camel case', () => {
    expect(toCamelCase('Qwe')).toBe('qwe')
  })

  it('shouldn\'t transform anything on empty string', () => {
    expect(toCamelCase('')).toBe('')
  })

  it('shouldn\'t transform string if its length is 1 char', () => {
    expect(toCamelCase('A')).toBe('A')
  })

  it('shouldn\'t transform string if it is undefined', () => {
    expect(toCamelCase(undefined)).toBe(undefined)
  })
})

describe('helpers/string: camel case to pascal case', () => {

  it('should transform string from pascal to camel case', () => {
    expect(toPascalCase('qwe')).toBe('Qwe')
  })

  it('shouldn\'t transform anything on empty string', () => {
    expect(toPascalCase('')).toBe('')
  })

  it('shouldn\'t transform string if its length is 1 char', () => {
    expect(toPascalCase('a')).toBe('a')
  })

  it('shouldn\'t transform string if it is undefined', () => {
    expect(toPascalCase(undefined)).toBe(undefined)
  })
})
