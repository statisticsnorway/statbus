import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { statUnitTypes } from 'helpers/enums'
import { createModel, updateProperties } from 'helpers/modelProperties'
import { navigateBack } from 'helpers/actionCreators'
import createSchema from '../createSchema'

const fetchStatUnit = (type, regId) =>
  dispatchRequest({
    url: `/api/StatUnits/GetUnitById/${type}/${regId}`,
    onSuccess: (dispatch, resp) => {
      const schema = createSchema(type)
      const model = schema.cast(createModel(resp))
      const patched = {
        ...resp,
        properties: updateProperties(model, resp.properties),
      }
    },
  })

const submitStatUnit = (type, data) =>
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
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
  navigateBack,
}
