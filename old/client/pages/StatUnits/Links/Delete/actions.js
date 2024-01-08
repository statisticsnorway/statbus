import { createAction } from 'redux-act'

import { notification } from '/helpers/actionCreators'
import dispatchRequest from '/helpers/request'

export const linkDeleteStarted = createAction('DeleteLink DeleteStarted')
export const linkDeleteSuccess = createAction('DeleteLink DeleteSuccess')
export const linkDeleteFailed = createAction('DeleteLink DeleteFailed')

export const deleteLink = data => disp =>
  new Promise((resolve) => {
    disp(notification.showNotification({
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
            resolve()
          },
          onFail: (dispatch) => {
            dispatch(linkDeleteFailed())
          },
        })(disp)
      },
    }))
  })

export default {
  deleteLink,
}
