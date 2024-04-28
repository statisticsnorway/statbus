import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

export const fetchRoleSucceeded = createAction('fetch role succeeded')

const fetchRole = id =>
  dispatchRequest({
    url: `/api/roles/${id}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchRoleSucceeded(resp))
    },
    onFail: (dispatch) => {
      dispatch(push('/roles'))
    },
  })

const submitRole = ({ id, ...data }) =>
  dispatchRequest({
    url: `/api/roles/${id}`,
    method: 'put',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/roles'))
    },
  })

export const editForm = createAction('edit role form')

export default {
  editForm,
  submitRole,
  fetchRole,
  navigateBack,
}
