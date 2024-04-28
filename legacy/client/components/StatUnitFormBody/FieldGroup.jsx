import React from 'react'
import PropTypes from 'prop-types'
import { Form } from 'semantic-ui-react'

const FieldGroup = ({ isExtended, children }) => (
  <Form.Group widths="equal">
    {children}
    {!isExtended && children.length % 2 !== 0 && <div className="field" />}
  </Form.Group>
)

const { bool, node } = PropTypes
FieldGroup.propTypes = {
  isExtended: bool.isRequired,
  children: node.isRequired,
}

export default FieldGroup
