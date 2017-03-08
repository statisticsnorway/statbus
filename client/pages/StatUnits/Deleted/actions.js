import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

const setQuery = query => (dispatch) => {
  dispatch(push({ query }))
}

export const fetchStatUnitSucceeded = createAction('fetch StatUnits succeeded')

const fetchData = queryParams => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/statunits/deleted',
    queryParams,
    onSuccess: (data) => {
      dispatch(fetchStatUnitSucceeded(data))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export const restoreSucceeded = createAction('restore StatUnit succeeded')

const restore = (type, regId) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    method: 'delete',
    url: '/api/statunits/deleted',
    queryParams: { type, regId },
    onSuccess: () => {
      dispatch(restoreSucceeded(regId))
      dispatch(rqstActions.succeeded())
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
    },
  })
}

export default {
  setQuery,
  fetchData,
  restore,
}
