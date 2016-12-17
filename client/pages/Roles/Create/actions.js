import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export default {
  submitRole: data => (dispatch) => {
    dispatch(rqstActions.started())
    rqst({
      url: '/api/roles',
      method: 'post',
      body: data,
      onSuccess: () => {
        dispatch(rqstActions.succeeded())
        browserHistory.push('/roles')
      },
      onFail: (errors) => { dispatch(rqstActions.failed(errors)) },
      onError: (errors) => { dispatch(rqstActions.failed(errors)) },
    })
  },
}
