import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export default {
  submitRole: data => (dispatch) => {
    dispatch(rqstActions.started(['submit role started']))
    rqst({
      url: '/api/roles',
      method: 'post',
      body: data,
      onSuccess: () => { dispatch(rqstActions.succeeded(['submit role succeeded'])) },
      onFail: (errors) => { dispatch(rqstActions.failed(['submit role failed', ...errors])) },
      onError: (errors) => { dispatch(rqstActions.failed(['submit role error', ...errors])) },
    })
  },
}
