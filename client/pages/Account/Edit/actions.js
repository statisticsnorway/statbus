import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

export const fetchAccountSucceeded = createAction('fetch account succeeded')
const fetchAccount = () => dispatchRequest({
  url: '/api/account/details',
  onSuccess: (dispatch, resp) => {
    dispatch(fetchAccountSucceeded(resp))
  },
})

const submitAccount = data => dispatchRequest({
  url: '/api/account/details',
  method: 'post',
  body: data,
  onSuccess: (dispatch) => {
    dispatch(push('/'))
  },
})

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
