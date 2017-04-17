import React from 'react'
import { arrayOf, func, shape } from 'prop-types'

import Form from 'components/Form'
import { operations, priorities } from 'helpers/dataSourceEnums'
import MappingsEditor from '../MappingsEditor'
import schema from '../schema'

const { Button, Select, Text } = Form
class Create extends React.Component {

  static propTypes = {
    columns: arrayOf(shape({})),
    localize: func.isRequired,
    actions: shape({
      fetchColumns: func.isRequired,
      submitData: func.isRequired,
    }).isRequired,
  }

  static defaultProps = {
    columns: [],
  }

  state = {
    formData: {
      name: '',
      description: '',
      allowedOperations: '',
      attributesToCheck: [],
      priority: 0,
      restrictions: '',
      variablesMapping: [],
    },
    attributes: [],
  }

  componentDidMount() {
    this.props.actions.fetchColumns()
  }

  handleMappingsChange = (value) => {
    this.setState(prev =>
      ({ formData: { ...prev.formData, variablesMapping: value } }))
  }

  handleEdit = (_, { name, value }) => {
    this.setState(prev =>
      ({ formData: { ...prev.formData, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.actions.submitData(this.state.formData)
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
        <Select
          name="attributesToCheck"
          value={attributesToCheck}
          onChange={this.handleEdit}
          options={allAttributes}
          multiple
        />
        <Select
          name="allowedOperations"
          value={allowedOperations}
          onChange={this.handleEdit}
          options={operations}
        />
        <Select
          name="priority"
          value={priority}
          onChange={this.handleEdit}
          options={priorities}
        />
        <MappingsEditor
          name="variablesMapping"
          value={variablesMapping}
          onChange={this.handleMappingsChange}
          attributes={allAttributes}
          columns={columns}
        />
        <Form.Message for="name" />
        <Button type="submit">{localize('Save')}</Button>
      </Form>
    )
  }
}

export default Create
