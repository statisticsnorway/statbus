import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import typeNames from 'helpers/statUnitTypes'
import { getModel as getModelFromProps, updateProperties } from 'helpers/modelProperties'
import { getSchema } from '../schema'

export const getModelSuccess = createAction('get model success')
export const setErrors = createAction('set errors')

export const getModel = type =>
  dispatchRequest({
    url: `/api/statunits/getnewentity/${typeNames.get(Number(type))}`,
    method: 'get',
    onSuccess: (dispatch, data) => {
      const model = getSchema(type).cast(getModelFromProps(data))
      const patched = {
        ...data,
        properties: updateProperties(model, data.properties),
      }
      dispatch(getModelSuccess(patched))
    },
  })

export const submitStatUnit = ({ type, ...data }) =>
  dispatchRequest({
    url: `/api/statunits/${typeNames.get(Number(type))}`,
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/statunits'))
    },
    onFail: (dispatch, errors) => {
      dispatch(setErrors(errors))
    },
  })

export const changeType = createAction('change type')

export const editForm = createAction('edit statUnit form')
