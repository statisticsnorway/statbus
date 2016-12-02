import { browserHistory } from 'react-router'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export default {
  submitUser: data => (dispatch) => {
    dispatch(rqstActions.started())
    rqst({
      url: '/api/users',
      method: 'post',
      body: data,
      onSuccess: () => {
        dispatch(rqstActions.succeeded())
        browserHistory.push('/users')
      },
      onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
      onError: (errors) => { dispatch(rqstActions.failed(errors)) },
    })
  },
}
