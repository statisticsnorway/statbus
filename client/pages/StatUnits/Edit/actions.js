import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'
import { statUnitTypes } from 'helpers/enums'

const clear = createAction('clear create statunit')
const setMeta = createAction('fetch model succeeded')
const setErrors = createAction('fetch model failed')

const fetchMeta = (type, regId) =>
  dispatchRequest({
    url: `/api/StatUnits/GetUnitById/${type}/${regId}`,
    onStart: (dispatch) => {
      dispatch(clear())
    },
    onSuccess: (dispatch, data) => {
      dispatch(setMeta(data))
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
