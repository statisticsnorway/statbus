import { push } from 'react-router-redux'

import dispatchRequest from '/client/helpers/request'
import { navigateBack } from '/client/helpers/actionCreators'

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
