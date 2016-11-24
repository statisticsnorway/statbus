import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export default {
  submitUser: data => (dispatch) => {
    dispatch(rqstActions.started(['submit user started']))
    rqst({
      url: '/api/users',
      method: 'post',
      body: data,
      onSuccess: () => { dispatch(rqstActions.succeeded(['submit user succeeded'])) },
      onFail: (errors) => { dispatch(rqstActions.failed(['submit user failed', ...errors])) },
      onError: (errors) => { dispatch(rqstActions.failed(['submit user error', ...errors])) },
    })
  },
}
