import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

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
  onSuccess: () => {
    browserHistory.push('/')
  },
})

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
