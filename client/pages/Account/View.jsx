import React from 'react'
import { Link } from 'react-router'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'
import { equals, pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from 'components/withSpinnerUnless'
import Info from 'components/Info'
import { wrapper } from 'helpers/locale'
import { internalRequest } from 'helpers/request'

const { string, func } = PropTypes

const hooks = {
  componentDidMount() {
    internalRequest({
      url: '/api/account/details',
      onSuccess: ({ name, email, phone }) => {
        this.setState({ name, email, phone, fetching: false })
      },
    })
  },
  shouldComponentUpdate(nextProps) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !equals(this.props, nextProps)
  },
}

const ViewPage = ({ name, phone, email, localize }) => (
  <div>
    <h2>
      {localize('AccountView')}
      {' '}
      <Link to="account/edit">{localize('Edit')}</Link>
    </h2>
    <Segment>
      {name && <Info label={localize('UserName')} text={name} />}
      {phone && <Info label={localize('Phone')} text={phone} />}
      {email && <Info label={localize('Email')} text={email} />}
    </Segment>
  </div>
)

ViewPage.propTypes = {
  name: string,
  phone: string,
  email: string,
  localize: func.isRequired,
}

ViewPage.defaultProps = {
  name: '',
  phone: '',
  email: '',
}

const enhance = pipe(
  wrapper,
  withSpinnerUnless(props => !props.fetching),
  lifecycle(hooks),
)

export default enhance(ViewPage)
