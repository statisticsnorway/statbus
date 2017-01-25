import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchUserSucceeded = createAction('fetch user succeeded')

const fetchUser = id => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/users/${id}`,
    onSuccess: (resp) => {
      dispatch(fetchUserSucceeded(resp))
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

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')
const submitUser = ({ id, ...data }) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/users/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
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

export const editForm = createAction('edit user form')

export default {
  editForm,
  submitUser,
  fetchUser,
}
