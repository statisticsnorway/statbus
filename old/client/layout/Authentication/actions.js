import dispatchRequest from '/helpers/request'
import { authentication } from '/helpers/actionCreators'

const hideAuthentication = () => dispatch => dispatch(authentication.hideAuthentication())

const sendAuthenticationRequest = data =>
  dispatchRequest({
    url: '/account/loginjs',
    method: 'post',
    body: data,
    onSuccess: (dispatch) => {
      dispatch(authentication.hideAuthentication())
    },
  })

export default {
  sendAuthenticationRequest,
  hideAuthentication,
}
