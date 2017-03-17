import { createAction } from 'redux-act'

import dispatchRequest from 'helpers/request'

export const fetchRolesSucceeded = createAction('fetch roles succeeded')

const fetchRoles = () =>
  dispatchRequest({
    onSuccess: (dispatch, resp) => {
      dispatch(fetchRolesSucceeded(resp))
    },
  })

export const deleteRoleSucceeded = createAction('delete role succeeded')

const deleteRole = id =>
  dispatchRequest({
    url: `/api/roles/${id}`,
    method: 'delete',
    onSuccess: (dispatch) => {
      dispatch(deleteRoleSucceeded(id))
    },
  })

export const fetchRoleUsersStarted = createAction('fetch role users started')
export const fetchRoleUsersSucceeded = createAction('fetch role users succeeded')
export const fetchRoleUsersFailed = createAction('fetch role users failed')

const fetchRoleUsers = id =>
  dispatchRequest({
    url: `/api/roles/${id}/users`,
    onStart: (dispatch) => {
      dispatch(fetchRoleUsersStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchRoleUsersSucceeded({ id, users: resp }))
    },
    onFail: (dispatch, errors) => {
      dispatch(fetchRoleUsersFailed(errors))
    },
  })

export default {
  fetchRoles,
  deleteRole,
  fetchRoleUsers,
}
