import { push } from 'react-router-redux'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

const submitRole = data =>
  dispatchRequest({
    url: '/api/roles',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/roles'))
    },
  })

export default {
  navigateBack,
  submitRole,
}
