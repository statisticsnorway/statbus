import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchRoleSucceeded = createAction('fetch role succeeded')

const fetchRole = id => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: `/api/roles/${id}`,
    onSuccess: (resp) => {
      dispatch(fetchRoleSucceeded(resp))
      dispatch(rqstActions.succeeded())
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

const submitRole = ({ id, ...data }) => (dispatch) => {
  dispatch(rqstActions.started())
  rqst({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      browserHistory.push('/roles')
    },
    onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
    onError: (errors) => { dispatch(rqstActions.failed(errors)) },
  })
}

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
}
