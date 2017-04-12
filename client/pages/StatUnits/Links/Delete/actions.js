import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'
import { actions as notificationActions } from 'helpers/notification'

export const linkDeleteStarted = createAction('DeleteLink DeleteStarted')
export const linkDeleteSuccess = createAction('DeleteLink DeleteSuccess')
export const linkDeleteFailed = createAction('DeleteLink DeleteFailed')

export const deleteLink = data => (disp) => {
  disp(notificationActions.showNotification({
    title: 'DialogTitleDelete',
    body: 'LinkDeleteConfirm',
    onConfirm: () => {
      dispatchRequest({
        url: '/api/links',
        method: 'delete',
        body: data,
        onStart: (dispatch) => {
          dispatch(linkDeleteStarted())
        },
        onSuccess: (dispatch) => {
          dispatch(linkDeleteSuccess())
        },
        onFail: (dispatch) => {
          dispatch(linkDeleteFailed())
        },
      })(disp)
    },
  }))
}

export default {
  deleteLink,
}

