import { checkProps } from 'layout/Breadcrumbs'

describe('layout/Breadcrumbs: checkProps for shouldUpdate', () => {

  it('should return true if localize.lang is different', () => {
    const props = { localize: _ => _, routes: [''] }
    const nextProps = { localize: _ => _, routes: [''] }
    props.localize.lang = '1'
    nextProps.localize.lang = '2'
    expect(checkProps(props, nextProps)).toBe(true)
  })
})
