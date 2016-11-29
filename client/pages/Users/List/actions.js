import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchUsersSucceeded = createAction('fetch users succeeded')

const fetchUsers = () => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchUsersSucceeded(resp))
      dispatch(rqstActions.succeeded())
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export const deleteUserSucceeded = createAction('delete user succeeded')

const deleteUser = id => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteUserSucceeded(id))
      dispatch(rqstActions.succeeded())
      browserHistory.push('/users')
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export default {
  fetchUsers,
  deleteUser,
}
