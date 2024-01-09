import React from 'react'
import { connect } from 'react-redux'
import { Link } from 'react-router'
import PropTypes from 'prop-types'
import { Segment, Button } from 'semantic-ui-react'
import { equals, pipe } from 'ramda'
import { lifecycle } from 'recompose'

import withSpinnerUnless from '/components/withSpinnerUnless'
import Info from '/components/Info'
import { getText } from '/helpers/locale'
import { internalRequest } from '/helpers/request'

const { string, func } = PropTypes

const ViewPage = ({ name, phone, email, localize }) => (
  <div>
    <h2>
      {localize('AccountView')}
      <span>&nbsp;</span>
      <Button as={Link} to="/account/edit" icon="edit" color="blue" />
    </h2>
    <Segment>
      {name && <Info label={localize('UserName')} text={name} />}
      {phone && <Info label={localize('Phone')} text={phone} />}
      {email && <Info label={localize('Email')} text={email} />}
    </Segment>
  </div>
)

ViewPage.propTypes = {
  name: string.isRequired,
  phone: string.isRequired,
  email: string.isRequired,
  localize: func.isRequired,
}

const assert = props =>
  props.name !== undefined || props.phone !== undefined || props.email !== undefined

const hooks = {
  componentDidMount() {
    internalRequest({
      url: '/api/account/details',
      onSuccess: ({ name, email, phone }) => {
        this.setState({ name, email, phone })
      },
    })
  },
  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  },
}

const mapStateToProps = state => ({ localize: getText(state.locale) })

const enhance = pipe(withSpinnerUnless(assert), lifecycle(hooks), connect(mapStateToProps))

export default enhance(ViewPage)
