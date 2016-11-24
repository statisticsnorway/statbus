import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchUsersSucceeded = createAction('fetch users succeeded')

const fetchUsers = () => (dispatch) => {
  dispatch(rqstActions.started(['fetch users started']))
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchUsersSucceeded(resp))
      dispatch(rqstActions.succeeded(['fetch users succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['delete users failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['delete users error', ...errors])) },
  })
}

export const deleteUserSucceeded = createAction('delete user succeeded')

const deleteUser = id => (dispatch) => {
  dispatch(rqstActions.started(['delete users started']))
  rqst({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteUserSucceeded(id))
      dispatch(rqstActions.succeeded(['delete user succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['delete users failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['delete users error', ...errors])) },
  })
}

export default {
  fetchUsers,
  deleteUser,
}
