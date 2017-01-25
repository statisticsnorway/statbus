import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchRoleSucceeded = createAction('fetch role succeeded')

const fetchRole = id => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/roles/${id}`,
    onSuccess: (resp) => {
      dispatch(fetchRoleSucceeded(resp))
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

const submitRole = ({ id, ...data }) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
      browserHistory.push('/roles')
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

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
}
