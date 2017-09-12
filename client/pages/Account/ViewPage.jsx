import React from 'react'
import PropTypes from 'prop-types'
import { Loader } from 'semantic-ui-react'
import R from 'ramda'

import Info from 'components/Info'
import { wrapper } from 'helpers/locale'
import { internalRequest } from 'helpers/request'

class ViewPage extends React.Component {

  static propTypes = {
    localize: PropTypes.func.isRequired,
  }

  state = {
    fetched: false,
    account: undefined,
  }

  componentDidMount() {
    this.fetchAccountInfo()
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
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
              {name && <Info label={localize('UserName')} text={name} />}
              {phone && <Info label={localize('Phone')} text={phone} />}
              {email && <Info label={localize('Email')} text={email} />}
            </div>
          )}
      </div>
    )
  }
}

export default wrapper(ViewPage)
