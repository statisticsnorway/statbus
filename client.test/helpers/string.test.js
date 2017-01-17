import str from '../../client/helpers/string'

describe('helpers/string: camel case to pascal case', () => {
  it('should transform string from pascal to camel case', () => {
    expect(str.pascalCaseToCamelCase('Qwe')).toBe('qwe')
  })
})
