import { createAction } from 'redux-act'

import { reduxRequest } from 'helpers/request'

export const linkSearchStarted = createAction('linkSearchStarted')

export const findUnit = filter => (
  reduxRequest({
    url: '/api/links/search',
    method: 'get',
    queryParams: filter,
    onStart: (dispatch) => {
      dispatch(linkSearchStarted(filter))
    },
  })
)

export const getUnitLinks = data => (
  reduxRequest({
    url: '/api/links',
    queryParams: data,
  })
)

export const getNestedLinks = data => (
  reduxRequest({
    url: '/api/links/nested',
    queryParams: data,
  })
)

export default {
  findUnit,
  getUnitLinks,
  getNestedLinks,
}
