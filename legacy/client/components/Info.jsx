import React from 'react'
import PropTypes from 'prop-types'

const Info = ({ label, text }) => {
  const id = `${label}.${text}`
  return (
    <p id={id} title={label}>
      <strong>
        <label htmlFor={id}>{label}: </label>
      </strong>
      {text}
    </p>
  )
}

const { number, oneOfType, string } = PropTypes
Info.propTypes = {
  label: string,
  text: oneOfType([number, string]),
}

Info.defaultProps = {
  label: '',
  text: '',
}

export default Info
