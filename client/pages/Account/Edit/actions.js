import { createAction } from 'redux-act'

import rqst from '../../../helpers/request'
import { actions as rqstActions } from '../../../helpers/requestStatus'

export const fetchAccountSucceeded = createAction('fetch account succeeded')
const fetchAccount = () => (dispatch) => {
  dispatch(rqstActions.started(['fetch account started']))
  rqst({
    url: '/api/account/details',
    onSuccess: (resp) => {
      dispatch(rqstActions.succeeded(['fetch account succeeded']))
      dispatch(fetchAccountSucceeded(resp))
    },
    onFail: (errors) => { dispatch(rqstActions.failed(['fetch account failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['fetch account error', ...errors])) },
  })
}

const submitAccount = data => (dispatch) => {
  dispatch(rqstActions.started(['submit account started']))
  rqst({
    url: '/api/account/details',
    method: 'post',
    body: data,
    onSuccess: () => { dispatch(rqstActions.succeeded(['submit account succeeded'])) },
    onFail: (errors) => { dispatch(rqstActions.failed(['submit account failed', ...errors])) },
    onError: (errors) => { dispatch(rqstActions.failed(['submit account error', ...errors])) },
  })
}

export const editForm = createAction('edit account form')

export default {
  editForm,
  submitAccount,
  fetchAccount,
}
