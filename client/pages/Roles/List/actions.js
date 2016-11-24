import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchRolesSucceeded = createAction('fetch roles succeeded')

const fetchRoles = () => (dispatch) => {
  dispatch(rqstActions.started(['fetch roles started']))
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchRolesSucceeded(resp))
      dispatch(rqstActions.succeeded(['fetch roles succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['fetch roles failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['fetch roles error', ...errors])) },
  })
}

export const deleteRoleSucceeded = createAction('delete role succeeded')

const deleteRole = id => (dispatch) => {
  dispatch(rqstActions.started('delete role started'))
  rqst({
    url: `/api/roles/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteRoleSucceeded(id))
      dispatch(rqstActions.succeeded(['delete role succeeded']))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['delete role failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['delete role error', ...errors])) },
  })
}

export const fetchRoleUsersStarted = createAction('fetch role users started')
export const fetchRoleUsersSucceeded = createAction('fetch role users succeeded')
export const fetchRoleUsersFailed = createAction('fetch role users failed')

const fetchRoleUsers = id => (dispatch) => {
  dispatch(fetchRoleUsersStarted())
  dispatch(rqstActions.started(['fetch role started']))
  rqst({
    url: `/api/roles/${id}/users`,
    onSuccess: (resp) => {
      dispatch(fetchRoleUsersSucceeded({ id, users: resp }))
      dispatch(rqstActions.succeeded(['fetch role succeeded']))
    },
    onFail: (errors) => {
      dispatch(fetchRoleUsersFailed('fetch role failed'))
      dispatch(rqstActions.failed(['fetch role failed', ...errors]))
    },
    onError: (errors) => {
      dispatch(fetchRoleUsersFailed('fetch role error'))
      dispatch(rqstActions.failed(['fetch role error', ...errors]))
    },
  })
}

export default {
  fetchRoles,
  deleteRole,
  fetchRoleUsers,
}
