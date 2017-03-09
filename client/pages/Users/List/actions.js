import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchUsersSucceeded = createAction('fetch users succeeded')

const fetchUsers = filter => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    queryParams: filter,
    onSuccess: (resp) => {
      dispatch(fetchUsersSucceeded({ ...resp, filter}))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export const deleteUserSucceeded = createAction('delete user succeeded')

const deleteUser = id => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/users/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteUserSucceeded(id))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
      browserHistory.push('/users')
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export default {
  fetchUsers,
  deleteUser,
}
