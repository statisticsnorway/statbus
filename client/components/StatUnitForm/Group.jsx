import React from 'react'
import PropTypes from 'prop-types'
import { Form } from 'semantic-ui-react'

import Field from './Field'

const Group = ({ explicitKey, isExtended, content }) => (
  <Form.Group widths="equal" key={explicitKey}>
    {content.map(Field)}
    {!isExtended && content.length % 2 !== 0 &&
      <div className="field" />}
  </Form.Group>
)

const { arrayOf, bool, number, shape } = PropTypes
Group.propTypes = {
  explicitKey: number.isRequired,
  isExtended: bool.isRequired,
  content: arrayOf(shape({})).isRequired,
}

export default Group
