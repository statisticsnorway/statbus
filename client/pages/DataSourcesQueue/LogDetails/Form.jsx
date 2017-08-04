import React from 'react'
import PropTypes from 'prop-types'

const Form = ({ formData, submitLogEntry }) => (
  <div>
    {Object.entries(formData).map(([k, v]) => <p key={k}>{k}: {v && v.toString()}</p>)}
  </div>
)

const { func, shape } = PropTypes
Form.propTypes = {
  formData: shape({}).isRequired,
  submitLogEntry: func.isRequired,
}

export default Form
