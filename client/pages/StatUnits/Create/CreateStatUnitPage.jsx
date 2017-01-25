import React from 'react'

import CreateForm from './CreateForm'

class CreateStatUnitPage extends React.Component {
  componentDidMount() {
    const { actions, type } = this.props
    actions.getModel(type)
  }

  componentWillReceiveProps(newProps) {
    const { actions, type } = this.props
    const { type: newType } = newProps
    if (newType != type) {
      actions.getModel(newType)
    }
  }

  render() {
    const { actions: { submitStatUnit, changeType }, statUnitModel, type, errors } = this.props
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      const copy = {}
      Object.entries(formData).forEach(([k, v]) => copy[k] = v === '' ? null : v)
      submitStatUnit({ ...copy, type })
    }
    return (
      <CreateForm
        {...{
          handleSubmit,
          changeType,
          type,
          statUnitModel,
          errors,
        }}
      />
    )
  }
}

const { shape, func } = React.PropTypes

CreateStatUnitPage.propTypes = {
  actions: shape({
    changeType: func.isRequired,
    submitStatUnit: func.isRequired,
  }),
}

export default CreateStatUnitPage
