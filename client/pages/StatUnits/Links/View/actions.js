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
export default {
  findUnit,
}
