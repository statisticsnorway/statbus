import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'
import { getModel as getModelFromProps, updateProperties } from 'helpers/modelProperties'

import { getSchema } from '../schema'

export const getModelSuccess = createAction('get model success')
export const setErrors = createAction('set errors')

export const getModel = type =>
  (dispatch) => {
    const startedAction = rqstActions.started()
    const { data: { id: startedId } } = startedAction
    dispatch(startedAction)
    const typeName = typeNames.get(Number(type))
    return rqst({
      url: `/api/statunits/getnewentity/${typeName}`,
      method: 'get',
      onSuccess: (data) => {
        const model = getSchema(type).cast(getModelFromProps(data.properties))
        const patched = {
          ...data,
          properties: updateProperties(model, data.properties),
        }
        dispatch(getModelSuccess(patched))
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

export const submitStatUnit = ({ type, ...data }) =>
  (dispatch) => {
    const startedAction = rqstActions.started()
    const { data: { id: startedId } } = startedAction
    dispatch(startedAction)
    const typeName = typeNames.get(Number(type))
    return rqst({
      url: `/api/statunits/${typeName}`,
      method: 'post',
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

export const changeType = createAction('change type')

export const editForm = createAction('edit statUnit form')
