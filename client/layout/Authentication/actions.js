import dispatchRequest from '/client/helpers/request'
import { authentication } from '/client/helpers/actionCreators'

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
