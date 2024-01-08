import { createAction } from 'redux-act'

import dispatchRequest from '/helpers/request'

export const fetchUsersStarted = createAction('fetch users started')
export const fetchUsersSucceeded = createAction('fetch users succeeded')
export const fetchUsersFailed = createAction('fetch users failed')

const fetchUsers = filter =>
  dispatchRequest({
    queryParams: filter,
    onStart: (dispatch) => {
      dispatch(fetchUsersStarted(filter))
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUsersSucceeded({ ...resp, filter }))
    },
    onFail: (dispatch) => {
      dispatch(fetchUsersFailed())
    },
  })

const setUserStatus = (id, filter, suspend) =>
  dispatchRequest({
    url: `/api/users/${id}`,
    method: 'delete',
    queryParams: { isSuspend: suspend },
    onSuccess: (dispatch) => {
      const gridRefresh = fetchUsers(filter)
      gridRefresh(dispatch)
    },
  })

export default {
  fetchUsers,
  setUserStatus,
}
