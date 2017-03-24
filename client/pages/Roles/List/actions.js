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

export default {
  fetchRoles,
  deleteRole,
}
