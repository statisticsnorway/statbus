import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchAccountSucceeded = createAction('fetch account succeeded')
const fetchAccount = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: '/api/account/details',
    onSuccess: (resp) => {
      dispatch(fetchAccountSucceeded(resp))
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

const submitAccount = data => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
      browserHistory.push('/')
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
