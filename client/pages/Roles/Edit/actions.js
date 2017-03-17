import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import dispatchRequest from 'helpers/request'

export const fetchRoleSucceeded = createAction('fetch role succeeded')

const fetchRole = id =>
  dispatchRequest({
    url: `/api/roles/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchRoleSucceeded(resp))
    },
  })

const submitRole = ({ id, ...data }) =>
  dispatchRequest({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      browserHistory.push('/roles')
    },
  })

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
}
