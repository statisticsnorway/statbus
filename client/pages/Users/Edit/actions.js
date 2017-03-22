import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export const fetchUserSucceeded = createAction('fetch user succeeded')

const fetchUser = id =>
  dispatchRequest({
    url: `/api/users/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUserSucceeded(resp))
    },
  })

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')

const submitUser = ({ id, ...data }) =>
  dispatchRequest({
    url: `/api/users/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      browserHistory.push('/users')
    },
  })

export const editForm = createAction('edit user form')

export default {
  editForm,
  submitUser,
  fetchUser,
}
