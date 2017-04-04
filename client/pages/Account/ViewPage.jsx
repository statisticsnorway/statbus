import React from 'react'
import { Loader } from 'semantic-ui-react'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import { internalRequest } from 'helpers/request'

class ViewPage extends React.Component {

  static propTypes = {
    localize: React.PropTypes.func.isRequired,
  }

  state = {
    fetched: false,
    account: undefined,
  }

  componentDidMount() {
    this.fetchAccountInfo()
  }

  shouldComponentUpdate(nextProps, nextState) {
    if (this.props.localize.lang !== nextProps.localize.lang) return true
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  fetchAccountInfo = () => {
    internalRequest({
      url: '/api/account/details',
      onSuccess: ({ name, email, phone }) => {
        this.setState({ name, email, phone })
      },
    })
  }

  render() {
    const { localize } = this.props
    const { name, email, phone } = this.state.account
    return (
      <div>
        <h2>{localize('AccountView')}</h2>
        {this.state.account === undefined
          ? <Loader active />
          : (
            <div>
              {name && <p><strong>{localize('UserName')}:</strong> {name}</p>}
              {phone && <p><strong>{localize('Phone')}:</strong> {phone}</p>}
              {email && <p><strong>{localize('Email')}:</strong> {email}</p>}
            </div>
          )}
      </div>
    )
  }
}

export default wrapper(ViewPage)
