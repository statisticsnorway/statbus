import { createAction } from 'redux-act'

import dispatchRequest, { reduxRequest } from 'helpers/request'

export const linkSearchStarted = createAction('linkSearchStarted')
export const linkSearchSuccess = createAction('linkSearchSuccess')
export const linkSearchFailed = createAction('linkSearchFailed')

export const findUnit = filter =>
  dispatchRequest({
    url: '/api/links/search',
    method: 'get',
    queryParams: filter,
    onStart: (dispatch) => {
      dispatch(linkSearchStarted(filter))
    },
    onSuccess: (dispatch, response) => {
      dispatch(linkSearchSuccess(response))
    },
    onFail: (dispatch, errors) => {
      dispatch(linkSearchFailed(errors))
    },
  })

export const getUnitChildren = data => (
  reduxRequest({
    url: '/api/links',
    queryParams: data,
  })
)

export default {
  findUnit,
  getUnitChildren,
}
