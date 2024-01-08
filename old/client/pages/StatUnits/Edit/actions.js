import { createAction } from 'redux-act'
import { push, goBack } from 'react-router-redux'
import { NotificationManager } from 'react-notifications'
import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'
import { statUnitTypes } from '/helpers/enums'
import { getLocalizeText } from '/helpers/locale'

const clear = createAction('clear create statunit')
const setMeta = createAction('fetch model succeeded')
const fetchError = createAction('fetch error')

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
      dispatch(fetchError(errors))
    },
  })

const submitStatUnit = (type, data, formikBag) =>
  dispatchRequest({
    url: `/api/statunits/${statUnitTypes.get(Number(type))}`,
    method: 'put',
    body: { ...data, permissions: formikBag.props.permissions },
    onStart: () => {
      formikBag.started()
    },
    onSuccess: (dispatch) => {
      if (window.history.length > 1) {
        dispatch(goBack())
      } else {
        dispatch(push('/'))
      }
      NotificationManager.success(getLocalizeText('StatUnitEditSuccessfully'))
    },
    onFail: (_, errors) => {
      formikBag.failed(errors)
      NotificationManager.error(getLocalizeText('StatUnitEditError'))
    },
  })

export const actionTypes = {
  setMeta,
  fetchError,
  clear,
}

export const actionCreators = {
  fetchMeta,
  submitStatUnit,
  navigateBack,
}
