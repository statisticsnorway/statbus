import React from 'react'
import PropTypes from 'prop-types'

import { hasValue } from 'helpers/schema'

export const transform = x => ({
  ...x,
  value: x.id,
  label: hasValue(x.code) ? `${x.code} ${x.name}` : x.name,
})

export const render = ({ name, code }) => (
  <div className="content">
    <div className="title">{name}</div>
    <strong className="description">{code}</strong>
  </div>
)

const { string } = PropTypes
render.propTypes = {
  name: string.isRequired,
  code: string.isRequired,
}
