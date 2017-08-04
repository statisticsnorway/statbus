import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { statUnitTypes } from 'helpers/enums'
import { createModel, updateProperties } from 'helpers/modelProperties'
import createSchema from '../createSchema'

const clear = createAction('clear statUnit before create')
const fetchModelSuccess = createAction('fetch model success')
const fetchModel = type =>
  dispatchRequest({
    url: `/api/statunits/getnewentity/${statUnitTypes.get(Number(type))}`,
    method: 'get',
    onStart: (dispatch) => {
      dispatch(clear())
    },
    onSuccess: (dispatch, data) => {
      const schema = createSchema(type)
      const model = schema.cast(createModel(data))
      const patched = {
        ...data,
        properties: updateProperties(model, data.properties),
      }
      dispatch(fetchModelSuccess({ statUnit: patched, schema }))
    },
  })

const setErrors = createAction('set errors')
const submitStatUnit = ({ type, ...data }) =>
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/statunits'))
    },
    onFail: (dispatch, errors) => {
      dispatch(setErrors(errors))
    },
  })

const changeType = createAction('change type')
const editForm = createAction('edit statUnit form')

export const actionTypes = {
  fetchModelSuccess,
  setErrors,
  clear,
  changeType,
  editForm,
}

export const actionCreators = {
  fetchModel,
  submitStatUnit,
  changeType,
  editForm,
}
