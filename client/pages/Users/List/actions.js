import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchUsersStarted = createAction('fetch users started')
export const fetchUsersSucceeded = createAction('fetch users succeeded')
export const fetchUsersFailed = createAction('fetch users failed')

const fetchUsers = () => (dispatch) => {
  dispatch(fetchUsersStarted())
  rqst({
    onSuccess: (resp) => { dispatch(fetchUsersSucceeded(resp)) },
    onFail: () => { dispatch(fetchUsersFailed('bad request')) },
    onError: () => { dispatch(fetchUsersFailed('request failed')) },
  })
}

export const deleteUserStarted = createAction('delete user started')
export const deleteUserSucceeded = createAction('delete user succeeded')
export const deleteUserFailed = createAction('delete user failed')

const deleteUser = id => (dispatch) => {
  dispatch(deleteUserStarted())
  rqst({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: () => { dispatch(deleteUserSucceeded(id)) },
    onFail: () => { dispatch(deleteUserFailed('bad request')) },
    onError: () => { dispatch(deleteUserFailed('request failed')) },
  })
}

export default {
  fetchUsers,
  deleteUser,
}
