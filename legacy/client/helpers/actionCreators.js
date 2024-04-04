import { createAction } from 'redux-act'
import { goBack } from 'react-router-redux'

import getUid from '/helpers/getUid'

export const navigateBack = () => dispatch => dispatch(goBack())

export const selectLocale = createAction('select locale')

const appendId = data => ({ ...data, id: getUid() })
export const request = {
  started: createAction('request started', appendId),
  succeeded: createAction('request succeeded', appendId),
  failed: createAction('request failed', appendId),
  dismiss: createAction('dismiss message'),
  dismissAll: createAction('dismiss all messages'),
}

export const notification = {
  showNotification: createAction('show notification'),
  hideNotification: createAction('hide notification'),
}

export const authentication = {
  showAuthentication: createAction('show authentication modal'),
  hideAuthentication: createAction('hide authentication modal'),
}
