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

export const deleteUsersStarted = createAction('delete user started')
export const deleteUsersSucceeded = createAction('delete user succeeded')
export const deleteUsersFailed = createAction('delete user failed')

const deleteUsers = id => (dispatch) => {
  dispatch(deleteUsersStarted())
  rqst({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: () => { dispatch(deleteUsersSucceeded(id)) },
    onFail: () => { dispatch(deleteUsersFailed('bad request')) },
    onError: () => { dispatch(deleteUsersFailed('request failed')) },
  })
}

export default {
  fetchUsers,
  deleteUsers,
}
