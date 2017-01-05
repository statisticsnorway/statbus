import { createAction } from 'redux-act'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchRolesSucceeded = createAction('fetch roles succeeded')

const fetchRoles = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    onSuccess: (resp) => {
      dispatch(fetchRolesSucceeded(resp))
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

export const deleteRoleSucceeded = createAction('delete role succeeded')

const deleteRole = id => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/roles/${id}`,
    method: 'delete',
    onSuccess: () => {
      dispatch(deleteRoleSucceeded(id))
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

export const fetchRoleUsersStarted = createAction('fetch role users started')
export const fetchRoleUsersSucceeded = createAction('fetch role users succeeded')
export const fetchRoleUsersFailed = createAction('fetch role users failed')

const fetchRoleUsers = id => (dispatch) => {
  dispatch(fetchRoleUsersStarted())
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  dispatch(startedAction)
  rqst({
    url: `/api/roles/${id}/users`,
    onSuccess: (resp) => {
      dispatch(fetchRoleUsersSucceeded({ id, users: resp }))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(fetchRoleUsersFailed())
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(fetchRoleUsersFailed())
      dispatch(rqstActions.failed({ errors }))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export default {
  fetchRoles,
  deleteRole,
  fetchRoleUsers,
}
