import React from 'react'
import PropTypes from 'prop-types'

const Form = ({ formData, submitData }) => (
  <div>
    {Object.entries(formData).map(([k, v]) => <p key={k}>{k}: {v && v.toString()}</p>)}
  </div>
)

const { func, shape } = PropTypes
Form.propTypes = {
  formData: shape({}).isRequired,
  submitData: func.isRequired,
}

export default Form
