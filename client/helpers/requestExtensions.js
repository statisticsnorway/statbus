import rqst from './request'
import { actions as rqstActions } from './requestStatus'

export default (request, dispatchStarted, dispatchSuccessed, dispatchFailure) => (dispatch) => {
  const startedAction = rqstActions.started()
  const startedId = startedAction.data.id
  if (dispatchStarted) dispatchStarted(dispatch)
  rqst({
    ...request,
    onSuccess: (resp) => {
      if (dispatchSuccessed) dispatchSuccessed(dispatch, resp)
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      if (dispatchFailure) dispatchFailure(dispatch, errors)
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      if (dispatchFailure) dispatchFailure(dispatch, errors)
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}
