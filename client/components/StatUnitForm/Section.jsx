import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'
import { equals } from 'ramda'
import { shouldUpdate } from 'recompose'

import Group from './Group'

const Section = ({ title, content }) => (
  <Segment>
    <Header as="h4" content={title} dividing />
    {content.map(Group)}
  </Segment>
)

const { arrayOf, shape, string } = PropTypes
Section.propTypes = {
  title: string,
  content: arrayOf(shape({})).isRequired,
}

Section.defaultProps = {
  title: 'Other',
  content: [],
}

const test = (prev, next) => prev.title !== next.title ||
  !equals(prev.content, next.content)

export default shouldUpdate(test)(Section)
