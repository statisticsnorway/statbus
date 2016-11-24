import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchRoleSucceeded = createAction('fetch role succeeded')

const fetchRole = id => (dispatch) => {
  dispatch(rqstActions.started(['fetch role started']))
  rqst({
    url: `/api/roles/${id}`,
    onSuccess: (resp) => {
      dispatch(fetchRoleSucceeded(resp))
      dispatch(rqstActions.succeeded(['fetch role succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['fetch role failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['fetch role error', ...errors])) },
  })
}

const submitRole = ({ id, ...data }) => (dispatch) => {
  dispatch(rqstActions.started(['submit role started']))
  rqst({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => { dispatch(rqstActions.succeeded(['submit role succeeded'])) },
    onFail: (errors) => { dispatch(rqstActions.failed(['submit role failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['submit role error', ...errors])) },
  })
}

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
}
