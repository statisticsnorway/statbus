import { createAction } from 'redux-act'
import { browserHistory } from 'react-router'

import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'
import typeNames from 'helpers/statUnitTypes'

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
      onSuccess: (model) => {
        dispatch(getModelSuccess(model))
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

