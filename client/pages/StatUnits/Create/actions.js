import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { statUnitTypes } from 'helpers/enums'
import { createModel, updateProperties } from 'helpers/modelProperties'
import { navigateBack } from 'helpers/actionCreators'
import createSchema from '../createSchema'

const changeType = type => dispatch => dispatch(push(`/statunits/create/${type}`))

const fetchModel = (type, onSuccess, onFail) =>
  dispatchRequest({
    url: `/api/statunits/getnewentity/${statUnitTypes.get(Number(type))}`,
    method: 'get',
    onSuccess: (dispatch, data) => {
      const schema = createSchema(type)
      const model = schema.cast(createModel(data))
      const patched = {
        ...data,
        properties: updateProperties(model, data.properties),
      }
      onSuccess({ statUnit: patched, schema })
    },
    onFail: (_, errors) => {
      onFail(errors)
    },
  })

const submitStatUnit = ({ type, ...data }, formActions) => {
  formActions.setSubmitting(true)
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      formActions.setSubmitting(false)
      dispatch(push('/statunits'))
    },
    onFail: (dispatch, errors) => {
      formActions.setSubmitting(false)
    },
  })
}

export default {
  fetchModel,
  changeType,
  submitStatUnit,
  navigateBack,
}
