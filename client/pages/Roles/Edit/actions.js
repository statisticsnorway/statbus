import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchRoleStarted = createAction('fetch role started')
export const fetchRoleSucceeded = createAction('fetch role started')
export const fetchRoleFailed = createAction('fetch role started')
const fetchRole = data => (dispatch) => {
  dispatch(fetchRoleStarted())
  rqst(
    '/api/roles',
    { id },
    'get',
    {},
    (resp) => { dispatch(fetchRoleSucceeded(resp)) },
    () => { dispatch(fetchRoleFailed('bad request')) },
    () => { dispatch(fetchRoleFailed('request failed')) }
  )
}

export const editRoleStarted = createAction('edit role started')
export const editRoleSucceeded = createAction('edit role succeeded')
export const editRoleFailed = createAction('edit role failed')
const editRole = ({ id, ...data }) => (dispatch) => {
  dispatch(editRoleStarted())
  rqst(
    '/api/roles',
    { id },
    'put',
    data,
    () => { dispatch(editRoleSucceeded()) },
    () => { dispatch(editRoleFailed('bad request')) },
    () => { dispatch(editRoleFailed('request failed')) }
  )
}
export default {
  editRole,
  fetchRole,
}
