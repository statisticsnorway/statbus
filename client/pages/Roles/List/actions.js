import { createAction } from 'redux-act'
import rqst from '../../../utils/fetch'

export const fetchRolesStarted = createAction('fetch roles started')
export const fetchRolesSucceeded = createAction('fetch roles succeeded')
export const fetchRolesFailed = createAction('fetch roles failed')

export default {
  fetchRoles: () => (dispatch) => {
    dispatch(fetchRolesStarted())
    rqst(
      '/api/roles',
      {},
      'get',
      {},
      (resp) => { dispatch(fetchRolesSucceeded(resp)) },
      () => { dispatch(fetchRolesFailed('bad request')) },
      () => { dispatch(fetchRolesFailed('request failed')) }
    )
  },
}
