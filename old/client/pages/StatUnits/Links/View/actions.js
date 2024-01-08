import { createAction } from 'redux-act'

import { reduxRequest } from '/helpers/request'

export const linkSearchStarted = createAction('linkSearchStarted')
export const clear = createAction('clear filter')

export const findUnit = filter =>
  reduxRequest({
    url: '/api/links/search',
    method: 'get',
    queryParams: filter,
    onStart: (dispatch) => {
      dispatch(linkSearchStarted(filter))
    },
  })

export default {
  findUnit,
  clear,
}
