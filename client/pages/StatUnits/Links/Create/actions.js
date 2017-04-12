import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'
import { actions as notificationActions } from 'helpers/notification'

export const linkCreateStarted = createAction('linkCreateStarted')
export const linkCreateSuccess = createAction('linkCreateSuccess')
export const linkCreateFailed = createAction('linkCreateFailed')

const overwriteLink = data =>
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
    onFail: (dispatch) => {
      dispatch(linkCreateFailed())
    },
  })

export const createLink = data =>
  dispatchRequest({
    url: '/api/links/CanBeLinked',
    method: 'get',
    queryParams: data,
    onStart: (dispatch) => {
      dispatch(linkCreateStarted())
    },
    onSuccess: (dispatch, resp) => {
      if (resp) {
        overwriteLink(data)(dispatch)
      } else {
        dispatch(notificationActions.showNotification({
          title: 'LinkUnits',
          body: 'LinkUnitAlreadyLinked',
          onConfirm: () => {
            overwriteLink(data)(dispatch)
          },
          onCancel: () => {
            dispatch(linkCreateFailed())
          },
        }))
      }
    },
    onFail: (dispatch, errors) => {
      dispatch(linkCreateFailed(errors))
    },
  })

export const linkDeleteSuccess = createAction('linkDeleteSuccess')

export const deleteLink = data => (disp) => {
  disp(notificationActions.showNotification({
    title: 'DialogTitleDelete',
    body: 'LinkDeleteConfirm',
    onConfirm: () => {
      dispatchRequest({
        url: '/api/links',
        method: 'delete',
        body: data,
        onSuccess: (dispatch) => {
          dispatch(linkDeleteSuccess(data))
        },
      })(disp)
    },
  }))
}


export default {
  createLink,
  deleteLink,
}
