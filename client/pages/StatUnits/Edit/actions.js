import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'
import { getModel as getModelFromProps, updateProperties } from 'helpers/modelProperties'
import { getSchema } from '../schema'

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

export const clear = createAction('clear')
export const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')

export const fetchStatUnit = (type, id) => (dispatch) => {
  const startedAction = rqstActions.started()
  const { data: { id: startedId } } = startedAction
  dispatch(startedAction)
  dispatch(clear())
  return rqst({
    url: `/api/StatUnits/GetUnitById/${type}/${id}`,
    onSuccess: (resp) => {
      const model = getSchema(type).cast(getModelFromProps(resp.properties))
      const patched = {
        ...resp,
        properties: updateProperties(model, resp.properties),
      }
      dispatch(fetchStatUnitSucceeded(patched))
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

export const editForm = createAction('edit statUnit form')

export default {
  submitStatUnit,
  fetchStatUnitSucceeded,
  fetchStatUnit,
}
