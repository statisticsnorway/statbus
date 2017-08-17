import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from 'helpers/request'
import { navigateBack } from 'helpers/actionCreators'
import { statUnitTypes } from 'helpers/enums'

const clear = createAction('clear create statunit')
const setMeta = createAction('fetch model succeeded')
const setErrors = createAction('fetch model failed')

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
    onFail: (dispatch, errors) => {
      dispatch(setErrors(errors))
    },
  })

const submitStatUnit = ({ type, ...data }, formActions) => {
  formActions.setSubmitting(true)
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/statunits'))
    },
    onFail: (errors) => {
      formActions.setSubmitting(false)
      formActions.setErrors(errors)
    },
  })
}

const changeType = type => dispatch => dispatch(push(`/statunits/create/${type}`))

export const actionTypes = {
  setMeta,
  setErrors,
  clear,
}

export const actionCreators = {
  fetchMeta,
  changeType,
  submitStatUnit,
  navigateBack,
}
