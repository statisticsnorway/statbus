import { createAction } from 'redux-act'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

export const fetchEnterpriseUnitsLookupSucceeded = createAction('fetch EnterpriseUnitsLookup succeeded')

export const fetchEnterpriseUnitsLookup = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/StatUnits/GetStatUnits/3',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchEnterpriseUnitsLookupSucceeded(resp))
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

export const fetchEnterpriseGroupsLookupSucceeded = createAction('fetch EnterpriseGroupsLookup succeeded')

export const fetchEnterpriseGroupsLookup = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/StatUnits/GetStatUnits/4',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchEnterpriseGroupsLookupSucceeded(resp))
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

export const fetchLegalUnitsLookupSucceeded = createAction('fetch LegalUnitsLookup succeeded')

export const fetchLegalUnitsLookup = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/StatUnits/GetStatUnits/2',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchLegalUnitsLookupSucceeded(resp))
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

export const fetchLocallUnitsLookupSucceeded = createAction('fetch LocallUnitsLookup succeeded')

export const fetchLocallUnitsLookup = () => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: '/api/StatUnits/GetStatUnits/1',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchLocallUnitsLookupSucceeded(resp))
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
