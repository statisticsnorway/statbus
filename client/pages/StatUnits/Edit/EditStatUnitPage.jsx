import React from 'react'

import { cloneFormObj } from 'helpers/queryHelper'
import EditForm from './EditForm'
import schema from '../schema'

class EditStatUnitPage extends React.Component {

  componentDidMount() {
    const { actions: { fetchStatUnit }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  handleSubmit = (e, { formData }) => {
    e.preventDefault()
    const { type, id, actions: { submitStatUnit, setErrors } } = this.props
    const data = { ...cloneFormObj(formData), regId: id }

    schema
      .validate(formData, { abortEarly: false })
      .then(() => submitStatUnit(type, data))
      .catch(({ inner }) => {
        const errors = inner.reduce(
          (acc, cur) => ({ ...acc, [cur.path]: cur.errors }),
          {},
        )
        setErrors(errors)
      })
  }

  render() {
    const { statUnit, errors } = this.props
    return (
      <EditForm
        statUnit={statUnit}
        errors={errors}
        handleSubmit={this.handleSubmit}
      />
    )
  }
}

const { string, shape, func } = React.PropTypes

EditStatUnitPage.propTypes = {
  id: string.isRequired,
  type: string.isRequired,
  actions: shape({
    fetchStatUnit: func,
  }).isRequired,
}

export default EditStatUnitPage
