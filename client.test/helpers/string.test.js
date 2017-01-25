import camelize from '../../client/helpers/stringToCamelCase'

describe('helpers/string: camel case to pascal case', () => {

  it('should transform string from pascal to camel case', () => {
    expect(camelize('Qwe')).toBe('qwe')
  })

  it('shouldn\'t transform anything on empty string', () => {
    expect(camelize('')).toBe('')
  })

  it('shouldn\'t transform string if its length is 1 char', () => {
    expect(camelize('A')).toBe('A')
  })

  it('shouldn\'t transform string if it is undefined', () => {
    expect(camelize(undefined)).toBe(undefined)
  })
})
