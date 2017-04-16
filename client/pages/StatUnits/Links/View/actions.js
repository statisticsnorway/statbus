import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

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
  dispatchRequest({
    url: '/api/links',
    queryParams: data,
    onSuccess: (dispatch, resp) => {
      //dispatch(linkSearchSuccess(resp))
    },
  })
)

export default {
  findUnit,
  getUnitChildren,
}
