import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchUserSucceeded = createAction('fetch user succeeded')
const fetchUser = id => (dispatch) => {
  dispatch(rqstActions.started(['fetch user started']))
  rqst({
    url: `/api/users/${id}`,
    onSuccess: (resp) => {
      dispatch(fetchUserSucceeded(resp))
      dispatch(rqstActions.succeeded(['fetch user succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['fetch user failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['fetch user error', ...errors])) },
  })
}

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')
const submitUser = ({ id, ...data }) => (dispatch) => {
  dispatch(rqstActions.started(['submit user started']))
  rqst({
    url: `/api/users/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => { dispatch(rqstActions.succeeded(['submit user succeeded'])) },
    onFail: (errors) => { dispatch(rqstActions.failed(['submit user failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['submit user error', ...errors])) },
  })
}

export const editForm = createAction('edit user form')

export default {
  editForm,
  submitUser,
  fetchUser,
}
