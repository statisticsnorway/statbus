import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

import Group from './Group'

const Section = ({ title, content }) => (
  <Segment key={title}>
    <Header as="h4" content={title} dividing />
    {content.map(Group)}
  </Segment>
)

const { node, string } = PropTypes
Section.propTypes = {
  title: string,
  content: node,
}

Section.defaultProps = {
  title: 'Other',
  content: [],
}

export default Section
