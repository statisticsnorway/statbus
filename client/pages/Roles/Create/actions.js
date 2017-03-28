import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'

export default {
  submitRole: data =>
  dispatchRequest({
    url: '/api/roles',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/roles'))
    },
  }),
}
