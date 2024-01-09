import { reduxRequest } from '/helpers/request'

export const getUnitLinks = data =>
  reduxRequest({
    url: '/api/links',
    queryParams: data,
  })

export const getNestedLinks = data =>
  reduxRequest({
    url: '/api/links/nested',
    queryParams: data,
  })

export default {
  getUnitLinks,
  getNestedLinks,
}
