import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { statUnitTypes } from 'helpers/enums'
import { createModel, updateProperties } from 'helpers/modelProperties'
import { navigateBack } from 'helpers/actionCreators'
import createSchema from '../createSchema'

const clear = createAction('clear create statunit')
const setMeta = createAction('fetch model succeeded')
const setErrors = createAction('fetch model failed')

const fetchMeta = (type, regId) =>
  dispatchRequest({
    url: `/api/StatUnits/GetUnitById/${type}/${regId}`,
    onSuccess: (dispatch, { properties, dataAccess }) => {
      const schema = createSchema(type)
      const meta = {
        properties: updateProperties(
          schema.cast(createModel(dataAccess, properties)),
          properties,
        ),
        dataAccess,
        schema,
      }
      dispatch(setMeta(meta))
    },
    onFail: (dispatch, errors) => {
      dispatch(setErrors(errors))
    },
  })

const submitStatUnit = ({ type, ...data }, formActions) => {
  formActions.setSubmitting(true)
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'put',
    body: data,
    onSuccess: push('/statunits'),
    onFail: (errors) => {
      formActions.setSubmitting(false)
      formActions.setErrors(errors)
    },
  })
}

export const actionTypes = {
  setMeta,
  setErrors,
  clear,
}

export const actionCreators = {
  fetchMeta,
  submitStatUnit,
  navigateBack,
}
