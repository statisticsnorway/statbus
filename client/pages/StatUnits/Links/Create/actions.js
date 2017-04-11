import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const linkCreateStarted = createAction('linkCreateStarted')
export const linkCreateSuccess = createAction('linkCreateSuccess')
export const linkCreateFailed = createAction('linkCreateFailed')

export const createLink = data =>
  dispatchRequest({
    url: '/api/links',
    method: 'post',
    body: data,
    onStart: (dispatch) => {
      dispatch(linkCreateStarted())
    },
    onSuccess: (dispatch) => {
      dispatch(linkCreateSuccess(data))
    },
    onFail: (dispatch, errors) => {
      dispatch(linkCreateFailed(errors))
    },
  })

export const linkDeleteSuccess = createAction('linkDeleteSuccess')

export const deleteLink = data =>
  dispatchRequest({
    url: '/api/links',
    method: 'delete',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(linkDeleteSuccess(data))
    },
  })

export default {
  createLink,
  deleteLink,
}
