import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchUsersSucceeded = createAction('fetch users succeeded')

const fetchUsers = filter =>
  dispatchRequest({
    queryParams: filter,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUsersSucceeded({ ...resp, filter }))
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
