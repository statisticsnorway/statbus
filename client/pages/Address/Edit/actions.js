import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

const submitAddress = ({ id, ...data }) =>
  dispatchRequest({
    url: `/api/addresses/${id}`,
    method: 'put',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/addresses'))
    },
  })

export const editForm = createAction('edit address form')

export default {
  editForm,
  submitAddress,
}
