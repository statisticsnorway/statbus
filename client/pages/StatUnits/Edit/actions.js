import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'

export const setErrors = createAction('set errors')

export const submitStatUnit = (type, data) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  const typeName = typeNames.get(Number(type))
  rqst({
    url: `/api/statunits/${typeName}`,
    method: 'put',
    body: data,
    onSuccess: () => {
      dispatch(rqstActions.succeeded())
      browserHistory.push('/statunits')
      dispatch(rqstActions.dismiss(startedId))
    },
    onFail: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
      dispatch(setErrors(errors))
    },
    onError: (errors) => {
      dispatch(rqstActions.failed(errors))
      dispatch(rqstActions.dismiss(startedId))
      dispatch(setErrors(errors))
    },
  })
}

export const editForm = createAction('edit stat unit form')
export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')

export const fetchStatUnit = (type, id) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  return rqst({
    url: `/api/StatUnits/GetUnitById/${type}/${id}`,
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded())
      dispatch(fetchStatUnitSucceeded(resp))
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
  editForm,
  submitStatUnit,
  fetchStatUnitSucceeded,
  fetchStatUnit,
}
