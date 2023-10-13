import React, { Component } from 'react'
import PropTypes from 'prop-types'
import { Form } from 'semantic-ui-react'

export class FieldGroup extends Component {
  render() {
    const { isExtended, children } = this.props
    return (
      <Form.Group widths="equal">
        {children}
        {!isExtended && children.length % 2 !== 0 && <div className="field" />}
      </Form.Group>
    )
  }
}

const { bool, node } = PropTypes
FieldGroup.propTypes = {
  isExtended: bool.isRequired,
  children: node.isRequired,
}

export default FieldGroup
