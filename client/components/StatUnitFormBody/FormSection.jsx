import React, { Component } from 'react'
import PropTypes from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

class FormSection extends Component {
  render() {
    const { id, title, children } = this.props

    return (
      <Segment id={id}>
        {title ? <Header as="h4" content={title} dividing /> : null}
        {children}
      </Segment>
    )
  }
}

const { node, string } = PropTypes
FormSection.propTypes = {
  id: string,
  title: string,
  children: node.isRequired,
}

FormSection.defaultProps = {
  id: undefined,
  title: 'Other',
}

export default FormSection
