import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

const FormSection = ({ title, children }) => (
  <Segment>
    <Header as="h4" content={title} dividing />
    {children}
  </Segment>
)

const { node, string } = PropTypes
FormSection.propTypes = {
  title: string,
  children: node.isRequired,
}

FormSection.defaultProps = {
  title: 'Other',
}

export default FormSection
