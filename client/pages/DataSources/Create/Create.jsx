import React from 'react'
import { arrayOf, func, shape } from 'prop-types'

import Form, { Button, Select, Text } from 'components/Form'
import { operations, priorities } from 'helpers/dataSourceEnums'
import schema from '../schema'

class Create extends React.Component {

  static propTypes = {
    columns: arrayOf(shape({})).isRequired,
    localize: func.isRequired,
    actions: shape({
      fetchColumns: func.isRequired,
      submit: func.isRequired,
    }).isRequired,
  }

  state = {
    formData: {
      name: '',
      description: '',
      allowedOperations: '',
      attributesToCheck: [],
      priority: 0,
      restrictions: '',
      variablesMapping: '',
    },
    attributes: [],
    nextAttribute: '',
  }

  componentDidMount() {
    this.props.actions.fetchColumns()
  }

  handleAttributeAdd = (name) => {
    this.setState(prev => ({
      attributes: [...prev.attributes, name].sort(),
      nextAttribute: '',
    }))
  }

  handleAttributeRemove = (name) => {
    this.setState(prev =>
      ({ attributes: prev.attributes.filter(x => x !== name) }))
  }

  handleWipeAttributes = () => {
    this.setState({ attributes: [] })
  }

  handleEditNextAttribute = (value) => {
    this.setState({ nextAttribute: value })
  }

  handleWipeNextAttribute = () => {
    this.handleEditNextAttribute('')
  }

  handleEdit = (_, { name, value }) => {
    this.setState(prev =>
      ({ formData: { ...prev.formData, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.actions.submit(this.state.formData)
  }

  render() {
    const { columns, localize } = this.props
    const {
      formData: {
        name, description, allowedOperations, priority,
        attributesToCheck, restrictions, variablesMapping,
      },
      attributes: allAttributes,
    } = this.state

    return (
      <Form schema={schema}>
        <Text name="name" value={name} onChange={this.handleEdit} />
        <Text name="description" value={description} onChange={this.handleEdit} />
        <Text name="restrictions" value={restrictions} onChange={this.handleEdit} />
        <Text name="variablesMapping" value={variablesMapping} onChange={this.handleEdit} />
        <Select name="attributesToCheck" value={attributesToCheck} onChange={this.handleEdit} options={allAttributes} />
        <Select name="allowedOperations" value={allowedOperations} onChange={this.handleEdit} options={operations} />
        <Select name="priority" value={priority} onChange={this.handleEdit} options={priorities} />
        <Button type="submit">{localize('Save')}</Button>
      </Form>
    )
  }
}

export default Create
