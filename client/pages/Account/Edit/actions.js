import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchAccountSucceeded = createAction('fetch account succeeded')
const fetchAccount = () => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: '/api/account/details',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchAccountSucceeded(resp))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

const submitAccount = data => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      browserHistory.push('/')
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
