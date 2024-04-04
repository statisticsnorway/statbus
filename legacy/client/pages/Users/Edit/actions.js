import { createAction } from 'redux-act'
import { push } from 'react-router-redux'

import dispatchRequest from '/helpers/request'
import { navigateBack } from '/helpers/actionCreators'

export const fetchUsersStarted = createAction('fetch user started')
export const fetchUserSucceeded = createAction('fetch user succeeded')

const fetchUser = id =>
  dispatchRequest({
    url: `/api/users/${id}`,
    onStart: (dispatch) => {
      dispatch(fetchUsersStarted())
    },
    onSuccess: (dispatch, resp) => {
      dispatch(fetchUserSucceeded(resp))
    },
    onFail: (dispatch) => {
      dispatch(push('/users'))
    },
  })

export const submitUserStarted = createAction('submit user started')
export const submitUserSucceeded = createAction('submit user succeeded')
export const submitUserFailed = createAction('submit user failed')
export const fechRegionTreeSucceeded = createAction('fetch region tree succeeded')

const submitUser = ({ id, ...data }) =>
  dispatchRequest({
    url: `/api/users/${id}`,
    method: 'put',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(push('/users'))
    },
  })

const fetchRegionTree = () =>
  dispatchRequest({
    url: '/api/Regions/GetAllRegionTree',
    method: 'get',
    onSuccess: (dispatch, resp) => {
      dispatch(fechRegionTreeSucceeded(resp))
    },
  })

export const fetchActivityTreeSucceded = createAction('fetch activity tree succeeded')

const fetchActivityTree = (parentId = 0) =>
  dispatchRequest({
    url: `/api/roles/fetchActivityTree?parentId=${parentId}`,
    onSuccess: (dispatch, resp) => {
      dispatch(fetchActivityTreeSucceded(resp))
    },
  })

export const editForm = createAction('edit user form')

export default {
  editForm,
  submitUser,
  fetchUser,
  fetchRegionTree,
  navigateBack,
  fetchActivityTree,
}
