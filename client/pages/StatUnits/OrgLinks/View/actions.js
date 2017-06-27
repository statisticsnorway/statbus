import { createAction } from 'redux-act'

import { reduxRequest } from 'helpers/request'

export const orgLinkSearchStarted = createAction('orgLinkSearchStarted')

export const findUnit = filter => (
  reduxRequest({
    url: '/api/Orglinks/fetch',
    method: 'get',
    queryParams: filter,
    onStart: (dispatch) => {
      dispatch(orgLinkSearchStarted(filter))
    },
  })
)
export default {
  findUnit,
}
