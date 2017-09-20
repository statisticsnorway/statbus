import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'
import { statUnitTypes } from 'helpers/enums'

const clear = createAction('clear create statunit')
const setMeta = createAction('fetch model succeeded')
const setErrors = createAction('fetch model failed')
const startSubmitting = createAction('start submitting form')
const stopSubmitting = createAction('stop submitting form')

const fetchMeta = type =>
  dispatchRequest({
    url: `/api/statunits/getnewentity/${statUnitTypes.get(Number(type))}`,
    method: 'get',
    onStart: (dispatch) => {
      dispatch(clear())
    },
    onSuccess: (dispatch, data) => {
      dispatch(setMeta(data))
    },
  })

const submitStatUnit = (type, data, formikBag) =>
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'post',
    body: { ...data, dataAccess: formikBag.props.dataAccess },
    onStart: (dispatch) => {
      formikBag.started()
      dispatch(startSubmitting())
    },
    onSuccess: (dispatch) => {
      dispatch(push('/statunits'))
    },
    onFail: (dispatch, errors) => {
      formikBag.failed(errors)
      dispatch(stopSubmitting())
    },
  })

const changeType = type => (dispatch) => {
  dispatch(push(`/statunits/create/${type}`))
}

export const actionTypes = {
  setMeta,
  setErrors,
  clear,
  startSubmitting,
  stopSubmitting,
}

export const actionCreators = {
  fetchMeta,
  changeType,
  submitStatUnit,
  navigateBack,
}
