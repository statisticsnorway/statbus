import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import typeNames from 'helpers/statUnitTypes'
import { createModel, updateProperties } from 'helpers/modelProperties'
import createSchema from '../createSchema'
import { customizePropNames } from '../propNamesCustomizer'

const clear = createAction('clear')
const fetchStatUnitSucceeded = createAction('fetch StatUnit succeeded')
const fetchStatUnit = (type, regId) =>
  dispatchRequest({
    url: `/api/StatUnits/GetUnitById/${type}/${regId}`,
    onStart: (dispatch) => {
      dispatch(clear())
    },
    onSuccess: (dispatch, resp) => {
      const schema = createSchema(type)
      const model = schema.cast(createModel(resp))
      const patched = {
        ...resp,
        properties: updateProperties(model, customizePropNames(resp.properties)),
      }
      console.log(patched)
      dispatch(fetchStatUnitSucceeded({ statUnit: patched, schema }))
    },
  })

const setErrors = createAction('set errors')
const submitStatUnit = (type, data) =>
  dispatchRequest({
    url: `/api/statunits/${typeNames.get(Number(type))}`,
    method: 'put',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/statunits'))
    },
    onFail: (dispatch, errors) => {
      dispatch(setErrors(errors))
    },
  })

const editForm = createAction('edit statUnit form')

export const actionTypes = {
  fetchStatUnitSucceeded,
  setErrors,
  clear,
  editForm,
}

export const actionCreators = {
  submitStatUnit,
  fetchStatUnit,
  editForm,
}
