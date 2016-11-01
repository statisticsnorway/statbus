import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchRoleStarted = createAction('fetch role started')
export const fetchRoleSucceeded = createAction('fetch role succeeded')
export const fetchRoleFailed = createAction('fetch role failed')
const fetchRole = id => (dispatch) => {
  dispatch(fetchRoleStarted())
  rqst({
    url: `/api/roles/${id}`,
    onSuccess: (resp) => { dispatch(fetchRoleSucceeded(resp)) },
    onFail: () => { dispatch(fetchRoleFailed('bad request')) },
    onError: () => { dispatch(fetchRoleFailed('request failed')) },
  })
}

export const submitRoleStarted = createAction('submit role started')
export const submitRoleSucceeded = createAction('submit role succeeded')
export const submitRoleFailed = createAction('submit role failed')
const submitRole = ({ id, ...data }) => (dispatch) => {
  dispatch(submitRoleStarted())
  rqst({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => { dispatch(submitRoleSucceeded()) },
    onFail: () => { dispatch(submitRoleFailed('bad request')) },
    onError: () => { dispatch(submitRoleFailed('request failed')) },
  })
}

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
}
