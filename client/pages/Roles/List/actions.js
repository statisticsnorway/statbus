import { createAction } from 'redux-act'
import rqst from '../../../helpers/fetch'

export const fetchRolesStarted = createAction('fetch roles started')
export const fetchRolesSucceeded = createAction('fetch roles succeeded')
export const fetchRolesFailed = createAction('fetch roles failed')

const fetchRoles = () => (dispatch) => {
  dispatch(fetchRolesStarted())
  rqst({
    onSuccess: (resp) => { dispatch(fetchRolesSucceeded(resp)) },
    onFail: () => { dispatch(fetchRolesFailed('bad request')) },
    onError: () => { dispatch(fetchRolesFailed('request failed')) },
  })
}

export const deleteRoleStarted = createAction('delete role started')
export const deleteRoleSucceeded = createAction('delete role succeeded')
export const deleteRoleFailed = createAction('delete role failed')

const deleteRole = id => (dispatch) => {
  dispatch(deleteRoleStarted())
  rqst({
    url: `/api/roles/${id}`,
    method: 'delete',
    onSuccess: () => { dispatch(deleteRoleSucceeded(id)) },
    onFail: () => { dispatch(deleteRoleFailed('bad request')) },
    onError: () => { dispatch(deleteRoleFailed('request failed')) },
  })
}

export const fetchRoleUsersStarted = createAction('fetch role users started')
export const fetchRoleUsersSucceeded = createAction('fetch role users succeeded')
export const fetchRoleUsersFailed = createAction('fetch role users failed')

const fetchRoleUsers = id => (dispatch) => {
  dispatch(fetchRoleUsersStarted())
  rqst({
    url: `/api/roles/${id}/users`,
    onSuccess: (resp) => { dispatch(fetchRoleUsersSucceeded({ id, users: resp })) },
    onFail: () => { dispatch(fetchRoleUsersFailed('bad request')) },
    onError: () => { dispatch(fetchRoleUsersFailed('request failed')) },
  })
}

export default {
  fetchRoles,
  deleteRole,
  fetchRoleUsers,
}
