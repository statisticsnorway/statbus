import React from 'react'
import { cloneFormObj } from 'helpers/queryHelper'
import EditForm from './EditForm'

class EditStatUnitPage extends React.Component {
  componentDidMount() {
    const { actions: { fetchStatUnit }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  onSubmit = (e, { formData }) => {
    const { type, id, actions: { submitStatUnit } } = this.props
    e.preventDefault()
    submitStatUnit(type, { ...cloneFormObj(formData), regId: id })
  }

  render() {
    const { statUnit, errors } = this.props
    return (
      <EditForm statUnit={statUnit} errors={errors} onSubmit={this.onSubmit} />
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
