import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

const FormSection = ({ id, title, children }) => (
  <Segment id={id}>
    {title ? <Header as="h4" content={title} dividing /> : null}
    {children}
  </Segment>
)

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
