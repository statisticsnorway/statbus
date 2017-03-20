import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export const fetchUsersSucceeded = createAction('fetch users succeeded')

const fetchUsers = filter =>
  dispatchRequest({
    queryParams: filter,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUsersSucceeded({ ...resp, filter }))
    },
  })

export const deleteUserSucceeded = createAction('delete user succeeded')

const deleteUser = id =>
  dispatchRequest({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteUserSucceeded(id))
      browserHistory.push('/users')
    },
  })

export default {
  fetchUsers,
  deleteUser,
}
